import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/member_photo_service.dart';
import '../../../core/services/offline_checkin_queue.dart';
import '../../../shared/widgets/member_photo.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

/// The gym's self check-in QR target. Members scan this (camera in their portal)
/// to record a visit. Same URL format the web app prints: gymcrm.in/c/{token}.
const _checkinBaseUrl = 'https://gymcrm.in/c/';

final _gymQrProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;
  return await client
      .from('gyms')
      .select('id, name, checkin_token')
      .eq('id', gymId)
      .maybeSingle();
});

final _recentCheckInsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final data = await client
      .from('check_ins')
      .select('id, member_id, checked_in_at, checked_out_at, method, members(first_name, last_name, email)')
      .eq('gym_id', gymId)
      .order('checked_in_at', ascending: false)
      .limit(20);

  return (data as List).cast<Map<String, dynamic>>();
});

// ── Small formatting helpers ─────────────────────────────────────────────────

final _timeFmt = DateFormat('h:mm a');

String _formatTime(String? s) {
  if (s == null) return '-';
  try {
    return _timeFmt.format(DateTime.parse(s).toLocal());
  } catch (_) {
    return s;
  }
}

/// "1h 09m" once past an hour, otherwise "55m".
String _formatDuration(String inAt, String outAt) {
  try {
    final d = DateTime.parse(outAt).toLocal().difference(DateTime.parse(inAt).toLocal());
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
  } catch (_) {
    return '-';
  }
}

Color _methodColor(String method) => switch (method) {
      'qr' => AppTheme.accent,
      'biometric' => const Color(0xFF7C3AED),
      _ => AppTheme.inkHint,
    };

/// Method badge as a plain colored dot rather than an icon glyph — new
/// Material icon glyphs grow the tree-shaken font, which Shorebird can't
/// patch (asset changes are excluded from patches).
class _MethodDot extends StatelessWidget {
  final String method;
  const _MethodDot({required this.method});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6, height: 6,
      decoration: BoxDecoration(color: _methodColor(method), shape: BoxShape.circle),
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  StreamSubscription<BarcodeCapture>? _barcodeSub;
  bool _processing = false;
  String? _message;
  bool _success = false;
  _CheckResult? _qrResult; // confirmation shown in the scanner card; pauses the camera
  int _pendingSync = 0;    // queued offline check-ins waiting to sync
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  int _tab = 0; // 0 = scan member, 1 = show gym QR

  @override
  void initState() {
    super.initState();
    _tryFlushQueue();
    _barcodeSub = _scanner.barcodes.listen((capture) {
      final barcode = capture.barcodes.firstOrNull;
      if (barcode?.rawValue != null) {
        _handleQrScan(barcode!.rawValue!);
      }
    });
  }

  @override
  void dispose() {
    _barcodeSub?.cancel();
    _scanner.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryFlushQueue() async {
    final count = await OfflineCheckInQueue.pendingCount();
    if (count == 0) return;
    if (!mounted) return;
    setState(() => _pendingSync = count);

    final online = await OfflineCheckInQueue.isOnline();
    if (!online) return;
    final synced = await OfflineCheckInQueue.flush();
    if (!mounted) return;
    final remaining = await OfflineCheckInQueue.pendingCount();
    setState(() => _pendingSync = remaining);
    if (synced > 0) ref.invalidate(_recentCheckInsProvider);
  }

  /// Core check-in: validates the member, blocks a second check-in on the same
  /// day (Asia/Kolkata), inserts the row, and returns the outcome. Does not
  /// touch the banner or the QR confirmation — the callers decide how to show it.
  Future<_CheckResult> _doCheckIn(String memberId, {String method = 'manual'}) async {
    setState(() => _processing = true);
    try {
      // If offline, enqueue and return immediately (QR only; manual needs names).
      if (method == 'qr') {
        final online = await OfflineCheckInQueue.isOnline();
        if (!online) {
          final gymId = await OfflineCheckInQueue.cachedGymId();
          if (gymId == null) {
            return const _CheckResult(
              success: false,
              title: 'No connection',
              subtitle: 'Check-in needs internet on first use. Connect once to enable offline mode.',
            );
          }
          final staffId = Supabase.instance.client.auth.currentUser?.id;
          if (staffId == null) {
            return const _CheckResult(
              success: false,
              title: 'Session expired',
              subtitle: 'Please sign in again to use offline check-in.',
            );
          }
          await OfflineCheckInQueue.enqueue(
            memberId: memberId,
            gymId: gymId,
            staffId: staffId,
          );
          final pending = await OfflineCheckInQueue.pendingCount();
          if (mounted) setState(() => _pendingSync = pending);
          return const _CheckResult(
            success: false,
            queued: true,
            title: 'Saved offline',
            subtitle: 'Will sync automatically when connected.',
          );
        }
      }

      final client = Supabase.instance.client;
      final gymId = await ref.read(gymIdProvider.future);

      // Cache gym_id after every successful network fetch so offline mode works.
      await OfflineCheckInQueue.cacheGymId(gymId);

      final member = await client
          .from('members')
          .select('id, first_name, last_name, status, avatar_url')
          .eq('id', memberId)
          .eq('gym_id', gymId)
          .maybeSingle();

      if (member == null) {
        return const _CheckResult(
          success: false,
          title: 'Member not found',
          subtitle: 'This QR code is not a member of your gym.',
        );
      }

      final name =
          '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim();
      final label = name.isNotEmpty ? name : 'Member';
      final avatarUrl = member['avatar_url'] as String?;

      if ((member['status'] as String) != 'active') {
        return _CheckResult(
          success: false,
          title: label,
          subtitle: 'Not active (${member['status']}). Check-in blocked.',
          avatarUrl: avatarUrl,
        );
      }

      try {
        await client.from('check_ins').insert({
          'member_id': memberId,
          'gym_id': gymId,
          'method': method,
          'staff_id': client.auth.currentUser?.id,
        });
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          return _CheckResult(
            success: false,
            already: true,
            title: label,
            subtitle: 'Already checked in. Check them out first.',
            avatarUrl: avatarUrl,
          );
        }
        rethrow;
      }
      ref.invalidate(_recentCheckInsProvider);

      return _CheckResult(
        success: true,
        title: label,
        subtitle: 'Checked in successfully.',
        avatarUrl: avatarUrl,
      );
    } catch (e) {
      return _CheckResult(success: false, title: 'Error', subtitle: '$e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Manual / search check-in — shows the transient banner at the top.
  Future<void> _processManual(String memberId) async {
    if (_processing) return;
    setState(() => _message = null);
    final r = await _doCheckIn(memberId, method: 'manual');
    if (!mounted) return;
    setState(() {
      _success = r.success;
      _message = r.subtitle != null ? '${r.title} — ${r.subtitle}' : r.title;
      if (r.success) {
        _searchResults = [];
        _searchCtrl.clear();
      }
    });
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _message = null);
  }

  Future<void> _processCheckOut(String checkInId, String memberName) async {
    if (_processing) return;
    setState(() => _message = null);
    setState(() => _processing = true);
    try {
      final client = Supabase.instance.client;
      await client.rpc('checkout_member', params: {'p_check_in_id': checkInId});
      ref.invalidate(_recentCheckInsProvider);
      if (!mounted) return;
      setState(() {
        _success = true;
        _message = '$memberName — Checked out successfully.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = 'Checkout failed: $e';
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _message = null);
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// QR check-in — freezes the camera and shows a full confirmation screen.
  Future<void> _handleQrScan(String raw) async {
    if (_processing || _qrResult != null) return;
    await _scanner.stop();
    final trimmed = raw.trim();
    if (!_uuidPattern.hasMatch(trimmed)) {
      if (!mounted) return;
      setState(() => _qrResult = const _CheckResult(
        success: false,
        title: 'Invalid QR Code',
        subtitle: 'This is not a GymCRM member QR code.',
      ));
      return;
    }
    final r = await _doCheckIn(trimmed, method: 'qr');
    if (!mounted) return;
    setState(() => _qrResult = r);
  }

  Future<void> _scanNext() async {
    setState(() => _qrResult = null);
    await _scanner.start();
  }

  Future<void> _searchMembers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      final q = '%${query.trim()}%';
      final data = await client
          .from('members')
          .select('id, first_name, last_name, email, status, avatar_url')
          .eq('gym_id', gymId)
          .or('first_name.ilike.$q,last_name.ilike.$q')
          .limit(10);

      if (mounted) {
        setState(() => _searchResults = (data as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('[GymCRM] Member search error: $e');
      if (mounted) setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final recentAsync = ref.watch(_recentCheckInsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  const Text('Check-in',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.ink, letterSpacing: -0.5)),
                  const Spacer(),
                  _HeaderIconButton(
                    icon: Icons.history,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const _HistoryPage()),
                    ),
                  ),
                ],
              ),
            ),
            if (_pendingSync > 0) _PendingSyncBanner(count: _pendingSync, onTap: _tryFlushQueue),
            if (_message != null) _ResultBanner(message: _message!, success: _success),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ScanTabSwitch(
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(
              child: _tab == 0
                  ? RefreshIndicator(
                      color: AppTheme.accent,
                      onRefresh: () async => ref.invalidate(_recentCheckInsProvider),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          _buildScannerCard(),
                          const SizedBox(height: 18),
                          Row(children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('or tap a name',
                                style: TextStyle(fontSize: 12, color: AppTheme.inkHint)),
                            ),
                            const Expanded(child: Divider()),
                          ]),
                          const SizedBox(height: 14),
                          _buildSearch(),
                          const SizedBox(height: 20),
                          _buildInToday(recentAsync),
                        ],
                      ),
                    )
                  : const _GymQrTab(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Scanner card ───────────────────────────────────────────────────────────

  Widget _buildScannerCard() {
    return Container(
      height: 250,
      decoration: AppTheme.darkCardDecoration(radius: 20),
      clipBehavior: Clip.antiAlias,
      child: _qrResult != null
          ? Container(
              color: AppTheme.surface,
              child: _CheckResultView(
                result: _qrResult!,
                onScanNext: _scanNext,
                buttonLabel: 'Scan next',
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _scanner),
                Center(
                  child: SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      children: [
                        Positioned(top: 0, left: 0, child: _CornerAccent(corner: _Corner.topLeft)),
                        Positioned(top: 0, right: 0, child: _CornerAccent(corner: _Corner.topRight)),
                        Positioned(bottom: 0, left: 0, child: _CornerAccent(corner: _Corner.bottomLeft)),
                        Positioned(bottom: 0, right: 0, child: _CornerAccent(corner: _Corner.bottomRight)),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  left: 0, right: 0, bottom: 18,
                  child: Text("Point at the member's QR",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onDark)),
                ),
                if (_processing)
                  Container(
                    color: Colors.black38,
                    child: const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
                  ),
              ],
            ),
    );
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Widget _buildSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: _searchMembers,
          decoration: InputDecoration(
            hintText: 'Search to check in',
            prefixIcon: const Icon(Icons.search, color: AppTheme.inkHint, size: 20),
            isDense: true,
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink)),
                  )
                : (_searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: AppTheme.inkHint),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchResults = []);
                        },
                      )
                    : null),
          ),
        ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            decoration: AppTheme.cardDecoration(),
            child: Column(
              children: _searchResults.map((m) => _SearchResultRow(
                member: m,
                processing: _processing,
                onCheckIn: () => _processManual(m['id'] as String),
              )).toList(),
            ),
          ),
        ],
        if (_searchCtrl.text.isNotEmpty && _searchResults.isEmpty && !_searching)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: Text('No members found',
              style: TextStyle(color: AppTheme.inkHint, fontSize: 13))),
          ),
      ],
    );
  }

  // ── In today ───────────────────────────────────────────────────────────────

  Widget _buildInToday(AsyncValue<List<Map<String, dynamic>>> recentAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('In today',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          const Spacer(),
          recentAsync.maybeWhen(
            data: (list) {
              final today = DateTime.now();
              final count = list.where((c) {
                final dt = DateTime.tryParse(c['checked_in_at'] as String? ?? '')?.toLocal();
                return dt != null && dt.year == today.year && dt.month == today.month && dt.day == today.day;
              }).length;
              return Text('$count',
                style: AppTheme.numberStyle(fontSize: 16, color: AppTheme.accent));
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ]),
        const SizedBox(height: 10),
        recentAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: $e', style: const TextStyle(color: AppTheme.statusDanger)),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: AppTheme.cardDecoration(),
                child: const Center(child: Text('No check-ins yet today',
                  style: TextStyle(color: AppTheme.inkHint, fontSize: 13))),
              );
            }
            return Container(
              decoration: AppTheme.cardDecoration(),
              child: Column(
                children: list.map((c) {
                  final isOpen = c['checked_out_at'] == null;
                  final member = c['members'] as Map<String, dynamic>?;
                  final name = '${member?['first_name'] ?? ''} ${member?['last_name'] ?? ''}'.trim();
                  return _RecentCheckInRow(
                    checkIn: c,
                    onCheckOut: isOpen && !_processing
                        ? () => _processCheckOut(c['id'] as String, name.isNotEmpty ? name : 'Member')
                        : null,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Header icon button ─────────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, size: 20, color: AppTheme.ink),
      ),
    );
  }
}

// ── Scan member / Show gym QR segmented switch ─────────────────────────────────

class _ScanTabSwitch extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _ScanTabSwitch({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.activeBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(context, 0, 'Scan member')),
          Expanded(child: _segment(context, 1, 'Show gym QR')),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, int i, String label) {
    final selected = index == i;
    return GestureDetector(
      onTap: () => onChanged(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 1))]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? AppTheme.ink : AppTheme.inkHint,
          ),
        ),
      ),
    );
  }
}

// ── Show gym QR tab (embedded) ───────────────────────────────────────────────

class _GymQrTab extends ConsumerWidget {
  const _GymQrTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymAsync = ref.watch(_gymQrProvider);

    return gymAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load gym QR: $e', style: const TextStyle(color: AppTheme.inkHint)),
        ),
      ),
      data: (gym) {
        final token = gym?['checkin_token']?.toString() ?? '';
        final gymName = gym?['name'] as String? ?? 'Your Gym';
        if (token.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No check-in code for this gym yet.', style: TextStyle(color: AppTheme.inkHint)),
            ),
          );
        }
        final url = '$_checkinBaseUrl$token';

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            children: [
              const Text(
                'Members scan this to check themselves in',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4))],
                ),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 200,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppTheme.ink),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppTheme.ink),
                ),
              ),
              const SizedBox(height: 20),
              Text(gymName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Check-in link copied'), duration: Duration(seconds: 2)),
                  );
                },
                child: const Text(
                  'Tap to copy check-in link',
                  style: TextStyle(fontSize: 12, color: AppTheme.inkHint, decoration: TextDecoration.underline),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const _GymQrPage()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Text(
                      'Full screen for front desk display',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Gym QR full-screen page (front-desk display) ────────────────────────────────

class _GymQrPage extends ConsumerStatefulWidget {
  const _GymQrPage();

  @override
  ConsumerState<_GymQrPage> createState() => _GymQrPageState();
}

class _GymQrPageState extends ConsumerState<_GymQrPage> {
  final _captureKey = GlobalKey();
  bool _saving = false;
  bool _sharing = false;

  Future<Uint8List?> _captureQrPng() async {
    final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  // Saves the QR card directly to the device's photo gallery via the `gal`
  // plugin (MediaStore on Android — no manual permission/manifest needed).
  Future<void> _saveToGallery(String gymName) async {
    setState(() => _saving = true);
    try {
      final bytes = await _captureQrPng();
      if (bytes == null) return;
      final safeName = gymName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
      await Gal.putImageBytes(bytes, album: 'GymCRM', name: 'gym_qr_$safeName');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to gallery')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the QR code. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Renders the QR card to a PNG and hands it to the system share sheet —
  // for printing or sending it elsewhere.
  Future<void> _shareQr(String gymName) async {
    setState(() => _sharing = true);
    try {
      final bytes = await _captureQrPng();
      if (bytes == null) return;

      final dir = await getTemporaryDirectory();
      final safeName = gymName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
      final file = await File('${dir.path}/gym_qr_$safeName.png').writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Scan to check in at $gymName',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share the QR code. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gymAsync = ref.watch(_gymQrProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Gym QR')),
      body: gymAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load gym QR: $e',
              style: const TextStyle(color: AppTheme.inkHint)),
        ),
      ),
      data: (gym) {
        final token = gym?['checkin_token']?.toString() ?? '';
        final gymName = gym?['name'] as String? ?? 'Your Gym';
        if (token.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No check-in code for this gym yet.',
                  style: TextStyle(color: AppTheme.inkHint)),
            ),
          );
        }
        final url = '$_checkinBaseUrl$token';

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RepaintBoundary(
                  key: _captureKey,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        QrImageView(
                          data: url,
                          version: QrVersions.auto,
                          size: 220,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppTheme.textPrimary,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          gymName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Members scan this to check themselves in.\nPrint it and place it at the front desk.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : () => _saveToGallery(gymName),
                    icon: _saving
                        ? const SizedBox(
                            height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save to gallery'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _sharing ? null : () => _shareQr(gymName),
                    icon: _sharing
                        ? const SizedBox(
                            height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink),
                          )
                        : const Icon(Icons.share_outlined, size: 18),
                    label: Text(_sharing ? 'Preparing…' : 'Share / Print'),
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Check-in link copied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            url,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.copy, size: 14, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap to copy check-in link',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }
}

// ── Pending sync banner ────────────────────────────────────────────────────────

class _PendingSyncBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _PendingSyncBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: AppTheme.statusWarnBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.history, color: AppTheme.statusWarn, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count check-in${count == 1 ? '' : 's'} saved offline — tap to sync now',
                style: const TextStyle(
                  color: AppTheme.statusWarn,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Result Banner ──────────────────────────────────────────────────────────────

class _ResultBanner extends StatelessWidget {
  final String message;
  final bool success;
  const _ResultBanner({required this.message, required this.success});

  @override
  Widget build(BuildContext context) {
    final bg = success ? AppTheme.statusActiveBg : AppTheme.statusDangerBg;
    final fg = success ? AppTheme.statusActive : AppTheme.statusDanger;
    final icon = success ? Icons.check_circle_outline : Icons.error_outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Check-in outcome + confirmation screen ──────────────────────────────────────

class _CheckResult {
  final bool success; // green — a fresh check-in was recorded
  final bool already; // amber — already checked in today
  final bool queued;  // amber — saved offline, will sync later
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  const _CheckResult({
    required this.success,
    this.already = false,
    this.queued = false,
    required this.title,
    this.subtitle,
    this.avatarUrl,
  });
}

class _MemberAvatar extends StatelessWidget {
  final String? url;
  final double size;
  const _MemberAvatar({this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final photoUrl = MemberPhotoService.photoUrl(url);
    if (photoUrl == null) return _InitialsAvatar(size: size);
    return CachedNetworkImage(
      imageUrl: photoUrl,
      httpHeaders: MemberPhotoService.authHeaders(),
      cacheKey: MemberPhotoService.pathFrom(url),
      imageBuilder: (_, img) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(image: img, fit: BoxFit.cover),
        ),
      ),
      placeholder: (_, __) => _InitialsAvatar(size: size),
      errorWidget: (_, __, ___) => _InitialsAvatar(size: size),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final double size;
  const _InitialsAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppTheme.activeBg,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person_outline, size: size * 0.5, color: AppTheme.inkSoft),
    );
  }
}

class _CheckResultView extends StatelessWidget {
  final _CheckResult result;
  final Future<void> Function() onScanNext;
  final String buttonLabel;
  const _CheckResultView({
    required this.result,
    required this.onScanNext,
    required this.buttonLabel,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    if (result.success) {
      bg = AppTheme.statusActiveBg;
      fg = AppTheme.statusActive;
      icon = Icons.check_circle_outline;
    } else if (result.already || result.queued) {
      bg = AppTheme.statusWarnBg;
      fg = AppTheme.statusWarn;
      icon = result.queued ? Icons.history : Icons.info_outline;
    } else {
      bg = AppTheme.statusDangerBg;
      fg = AppTheme.statusDanger;
      icon = Icons.error_outline;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Member photo (large) with status badge overlaid
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                _MemberAvatar(url: result.avatarUrl, size: 96),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(icon, color: fg, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              result.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            if (result.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                result.subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppTheme.inkHint),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => onScanNext(),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.ink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: Text(buttonLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── QR corner accent ───────────────────────────────────────────────────────────

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerAccent extends StatelessWidget {
  final _Corner corner;
  const _CornerAccent({required this.corner});

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    const width = 3.0;
    const color = AppTheme.accent;

    BorderRadius br;
    switch (corner) {
      case _Corner.topLeft:
        br = const BorderRadius.only(topLeft: Radius.circular(12));
      case _Corner.topRight:
        br = const BorderRadius.only(topRight: Radius.circular(12));
      case _Corner.bottomLeft:
        br = const BorderRadius.only(bottomLeft: Radius.circular(12));
      case _Corner.bottomRight:
        br = const BorderRadius.only(bottomRight: Radius.circular(12));
    }

    Border b;
    switch (corner) {
      case _Corner.topLeft:
        b = const Border(top: BorderSide(color: color, width: width), left: BorderSide(color: color, width: width));
      case _Corner.topRight:
        b = const Border(top: BorderSide(color: color, width: width), right: BorderSide(color: color, width: width));
      case _Corner.bottomLeft:
        b = const Border(bottom: BorderSide(color: color, width: width), left: BorderSide(color: color, width: width));
      case _Corner.bottomRight:
        b = const Border(bottom: BorderSide(color: color, width: width), right: BorderSide(color: color, width: width));
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(border: b, borderRadius: br),
    );
  }
}

// ── Search result row ─────────────────────────────────────────────────────────

class _SearchResultRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool processing;
  final VoidCallback onCheckIn;
  const _SearchResultRow({
    required this.member,
    required this.processing,
    required this.onCheckIn,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = member['first_name'] as String? ?? '';
    final lastName = member['last_name'] as String? ?? '';
    final email = member['email'] as String?;
    final avatarUrl = member['avatar_url'] as String?;
    final inits = initials(firstName, lastName);
    final isActive = (member['status'] as String?) == 'active';

    final initialsCircle = CircleAvatar(
      radius: 18,
      backgroundColor: AppTheme.activeBg,
      child: Text(
        inits,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: AppTheme.ink,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: MemberPhoto(stored: avatarUrl, fallback: initialsCircle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$firstName $lastName'.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.ink),
                ),
                if (email != null)
                  Text(email, style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
              ],
            ),
          ),
          if (!isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.statusDangerBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Inactive',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.statusDanger),
              ),
            )
          else
            SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: processing ? null : onCheckIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.ink,
                  foregroundColor: Colors.white,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('Check In'),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Recent check-in row (main "In today" list) ──────────────────────────────────

class _RecentCheckInRow extends StatelessWidget {
  final Map<String, dynamic> checkIn;
  final VoidCallback? onCheckOut;
  const _RecentCheckInRow({required this.checkIn, this.onCheckOut});

  @override
  Widget build(BuildContext context) {
    final member = checkIn['members'] as Map<String, dynamic>?;
    final firstName = member?['first_name'] as String? ?? '';
    final lastName = member?['last_name'] as String? ?? '';
    final email = member?['email'] as String?;
    final inits = initials(firstName, lastName);
    final method = checkIn['method'] as String? ?? 'manual';
    final checkedAt = checkIn['checked_in_at'] as String?;
    final checkedOut = checkIn['checked_out_at'] as String?;
    final isOpen = checkedOut == null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.activeBg,
                child: Text(
                  inits,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$firstName $lastName'.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.ink),
                    ),
                    if (email != null)
                      Text(email, style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _MethodDot(method: method),
                        const SizedBox(width: 3),
                        Text(
                          isOpen
                              ? 'In ${_formatTime(checkedAt)}'
                              : 'In ${_formatTime(checkedAt)} · Out ${_formatTime(checkedOut)}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCheckOut,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isOpen ? AppTheme.statusActiveBg : AppTheme.statusNeutralBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isOpen ? 'On floor' : _formatDuration(checkedAt!, checkedOut),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isOpen ? AppTheme.statusActive : AppTheme.statusNeutral,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16),
      ],
    );
  }
}

// ── History page ──────────────────────────────────────────────────────────────
// Filterable check-in log: date-range presets + member-name search, paginated.
// Mirrors the web app's check-in-history.tsx (same presets, same page size).

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

class _DatePreset {
  final String label;
  final (DateTime, DateTime) Function() range;
  const _DatePreset(this.label, this.range);
}

final List<_DatePreset> _historyPresets = [
  _DatePreset('Today', () {
    final s = _startOfDay(DateTime.now());
    return (s, s.add(const Duration(days: 1)));
  }),
  _DatePreset('Yesterday', () {
    final s = _startOfDay(DateTime.now()).subtract(const Duration(days: 1));
    return (s, s.add(const Duration(days: 1)));
  }),
  _DatePreset('Last 7 days', () {
    final end = _startOfDay(DateTime.now()).add(const Duration(days: 1));
    return (end.subtract(const Duration(days: 7)), end);
  }),
  _DatePreset('Last 30 days', () {
    final end = _startOfDay(DateTime.now()).add(const Duration(days: 1));
    return (end.subtract(const Duration(days: 30)), end);
  }),
];

class _HistoryPage extends StatelessWidget {
  const _HistoryPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 20, color: AppTheme.ink),
                  ),
                  const Text('History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink, letterSpacing: -0.3)),
                ],
              ),
            ),
            const Expanded(child: _HistoryTab()),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  static const _pageSize = 25;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  int _activePreset = 0;
  String _search = '';
  int _page = 1;
  int _count = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(int i) {
    if (i == _activePreset) return;
    setState(() {
      _activePreset = i;
      _page = 1;
    });
    _fetch();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _search = v.trim();
        _page = 1;
      });
      _fetch();
    });
  }

  void _nextPage() {
    if (_page * _pageSize >= _count) return;
    setState(() => _page++);
    _fetch();
  }

  void _prevPage() {
    if (_page <= 1) return;
    setState(() => _page--);
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final gymId = await ref.read(gymIdProvider.future);
      final (from, to) = _historyPresets[_activePreset].range();

      List<String>? memberIds;
      if (_search.isNotEmpty) {
        final q = '%$_search%';
        final matched = await client
            .from('members')
            .select('id')
            .eq('gym_id', gymId)
            .or('first_name.ilike.$q,last_name.ilike.$q');
        memberIds = (matched as List).map((m) => m['id'] as String).toList();
        if (memberIds.isEmpty) {
          if (mounted) setState(() { _items = []; _count = 0; _loading = false; });
          return;
        }
      }

      var query = client
          .from('check_ins')
          .select('id, checked_in_at, checked_out_at, method, members(first_name, last_name)')
          .eq('gym_id', gymId)
          .gte('checked_in_at', from.toUtc().toIso8601String())
          .lt('checked_in_at', to.toUtc().toIso8601String());

      if (memberIds != null) query = query.inFilter('member_id', memberIds);

      final start = (_page - 1) * _pageSize;
      final res = await query
          .order('checked_in_at', ascending: false)
          .range(start, start + _pageSize - 1)
          .count(CountOption.exact);

      if (!mounted) return;
      setState(() {
        _items = (res.data as List).cast<Map<String, dynamic>>();
        _count = res.count;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[GymCRM] Check-in history fetch error: $e');
      if (!mounted) return;
      setState(() {
        _items = [];
        _count = 0;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search member name...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.inkHint, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.ink, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_historyPresets.length, (i) {
                    final selected = i == _activePreset;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _selectPreset(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.ink : AppTheme.activeBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _historyPresets[i].label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? Colors.white : AppTheme.inkSoft,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetch,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'No check-ins found',
                              style: TextStyle(color: AppTheme.inkHint, fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                        itemBuilder: (_, i) => _HistoryCheckInRow(checkIn: _items[i]),
                      ),
          ),
        ),
        if (_count > _pageSize)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(_page - 1) * _pageSize + 1}–${((_page * _pageSize) < _count ? _page * _pageSize : _count)} of $_count',
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
                ),
                Row(
                  children: [
                    _PageArrow(label: '‹', onTap: _page > 1 ? _prevPage : null),
                    const SizedBox(width: 8),
                    _PageArrow(
                      label: '›',
                      onTap: (_page * _pageSize) < _count ? _nextPage : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// Plain-text pagination arrow — avoids touching the icon font (chevron_left
// isn't referenced anywhere else in the app; using Icons here would grow the
// tree-shaken MaterialIcons font and break Shorebird patchability).
class _PageArrow extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PageArrow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: enabled ? AppTheme.ink : AppTheme.border,
          ),
        ),
      ),
    );
  }
}

// ── History check-in row ──────────────────────────────────────────────────────

class _HistoryCheckInRow extends StatelessWidget {
  final Map<String, dynamic> checkIn;
  const _HistoryCheckInRow({required this.checkIn});

  @override
  Widget build(BuildContext context) {
    final member = checkIn['members'] as Map<String, dynamic>?;
    final firstName = member?['first_name'] as String? ?? '';
    final lastName = member?['last_name'] as String? ?? '';
    final name = '$firstName $lastName'.trim();
    final inits = initials(firstName, lastName);
    final method = checkIn['method'] as String? ?? 'manual';
    final checkedAt = checkIn['checked_in_at'] as String?;
    final checkedOut = checkIn['checked_out_at'] as String?;
    final isOpen = checkedOut == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.activeBg,
            child: Text(
              inits.isEmpty ? '?' : inits,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.ink),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unknown' : name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.ink),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _MethodDot(method: method),
                    const SizedBox(width: 3),
                    Text(
                      isOpen
                          ? 'In ${_formatTime(checkedAt)} · still on floor'
                          : 'In ${_formatTime(checkedAt)} · Out ${_formatTime(checkedOut)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isOpen ? AppTheme.statusActiveBg : AppTheme.statusNeutralBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isOpen ? 'Active' : _formatDuration(checkedAt!, checkedOut),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isOpen ? AppTheme.statusActive : AppTheme.statusNeutral,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
