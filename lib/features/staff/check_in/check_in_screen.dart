import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/member_photo_service.dart';
import '../../../core/services/offline_checkin_queue.dart';
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
      .select('*, members(first_name, last_name, email)')
      .eq('gym_id', gymId)
      .order('checked_in_at', ascending: false)
      .limit(10);

  return (data as List).cast<Map<String, dynamic>>();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final MobileScannerController _scanner = MobileScannerController();
  bool _processing = false;
  String? _message;
  bool _success = false;
  _CheckResult? _qrResult; // confirmation shown on the Scan tab; pauses the camera
  int _pendingSync = 0;    // queued offline check-ins waiting to sync
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChanged);
    _tryFlushQueue();
  }

  // Run the camera only while the Scan tab is active and no result is showing.
  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 0 && _qrResult == null) {
      _scanner.start();
    } else {
      _scanner.stop();
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
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

      // One check-in per calendar day (gym local day = Asia/Kolkata).
      final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final dayStartUtc = DateTime.utc(ist.year, ist.month, ist.day)
          .subtract(const Duration(hours: 5, minutes: 30));
      final existing = await client
          .from('check_ins')
          .select('id')
          .eq('member_id', memberId)
          .gte('checked_in_at', dayStartUtc.toIso8601String())
          .limit(1);
      if ((existing as List).isNotEmpty) {
        return _CheckResult(
          success: false,
          already: true,
          title: label,
          subtitle: 'Already checked in today.',
          avatarUrl: avatarUrl,
        );
      }

      await client.from('check_ins').insert({
        'member_id': memberId,
        'gym_id': gymId,
        'method': method,
        'staff_id': client.auth.currentUser?.id,
      });
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

  /// QR check-in — freezes the camera and shows a full confirmation screen.
  Future<void> _handleQrScan(String raw) async {
    if (_processing || _qrResult != null) return;
    await _scanner.stop();
    final r = await _doCheckIn(raw.trim(), method: 'qr');
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
          .select('id, first_name, last_name, email, status')
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Check-in'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Scan'),
            Tab(text: 'Gym QR'),
            Tab(text: 'Manual'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_pendingSync > 0) _PendingSyncBanner(count: _pendingSync, onTap: _tryFlushQueue),
          if (_message != null) _ResultBanner(message: _message!, success: _success),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildQrTab(), _buildGymQrTab(), _buildManualTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ── QR Tab ─────────────────────────────────────────────────────────────────

  Widget _buildQrTab() {
    if (_qrResult != null) {
      return _CheckResultView(
        result: _qrResult!,
        onScanNext: _scanNext,
        buttonLabel: 'Scan next',
      );
    }
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: _scanner,
                onDetect: (capture) {
                  final barcode = capture.barcodes.firstOrNull;
                  if (barcode?.rawValue != null) {
                    _handleQrScan(barcode!.rawValue!);
                  }
                },
              ),
              // Overlay frame
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.accent, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      // Corner accents
                      Positioned(
                        top: 0, left: 0,
                        child: _CornerAccent(corner: _Corner.topLeft),
                      ),
                      Positioned(
                        top: 0, right: 0,
                        child: _CornerAccent(corner: _Corner.topRight),
                      ),
                      Positioned(
                        bottom: 0, left: 0,
                        child: _CornerAccent(corner: _Corner.bottomLeft),
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: _CornerAccent(corner: _Corner.bottomRight),
                      ),
                    ],
                  ),
                ),
              ),
              if (_processing)
                Container(
                  color: Colors.black38,
                  child: const Center(
                    child: CircularProgressIndicator(color: AppTheme.accent),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Point camera at member QR code',
          style: const TextStyle(
            color: AppTheme.inkHint,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Gym QR Tab ─────────────────────────────────────────────────────────────

  Widget _buildGymQrTab() {
    final gymAsync = ref.watch(_gymQrProvider);

    return gymAsync.when(
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
                Container(
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
                const SizedBox(height: 24),
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
    );
  }

  // ── Manual Tab ─────────────────────────────────────────────────────────────

  Widget _buildManualTab() {
    final recentAsync = ref.watch(_recentCheckInsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_recentCheckInsProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search card
          Container(
            decoration: AppTheme.cardDecoration(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter Member Name or ID',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  onChanged: _searchMembers,
                  decoration: InputDecoration(
                    hintText: 'Search by name...',
                    prefixIcon: const Icon(Icons.search, color: AppTheme.inkHint, size: 20),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink),
                            ),
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
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  ..._searchResults.map((m) => _SearchResultRow(
                        member: m,
                        processing: _processing,
                        onCheckIn: () => _processManual(m['id'] as String),
                      )),
                ],
                if (_searchCtrl.text.isNotEmpty && _searchResults.isEmpty && !_searching) ...[
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'No members found',
                      style: TextStyle(color: AppTheme.inkHint, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Recent check-ins card
          Container(
            decoration: AppTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    children: [
                      const Text(
                        'Recent Check-ins',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.ink,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.history, size: 16, color: AppTheme.inkHint),
                    ],
                  ),
                ),
                const Divider(height: 1),
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
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No check-ins yet today',
                            style: TextStyle(color: AppTheme.inkHint, fontSize: 13),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: list
                          .map((c) => _RecentCheckInRow(checkIn: c))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
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
    if (url == null || url!.isEmpty) return _InitialsAvatar(size: size);
    return FutureBuilder<String?>(
      future: MemberPhotoService.signedUrl(url),
      builder: (context, snap) {
        final signed = snap.data;
        if (signed == null) return _InitialsAvatar(size: size);
        return CachedNetworkImage(
          imageUrl: signed,
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
      },
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
    final color = AppTheme.ink;

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
        b = Border(top: BorderSide(color: color, width: width), left: BorderSide(color: color, width: width));
      case _Corner.topRight:
        b = Border(top: BorderSide(color: color, width: width), right: BorderSide(color: color, width: width));
      case _Corner.bottomLeft:
        b = Border(bottom: BorderSide(color: color, width: width), left: BorderSide(color: color, width: width));
      case _Corner.bottomRight:
        b = Border(bottom: BorderSide(color: color, width: width), right: BorderSide(color: color, width: width));
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
    final inits = initials(firstName, lastName);
    final isActive = (member['status'] as String?) == 'active';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
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

// ── Recent check-in row ────────────────────────────────────────────────────────

class _RecentCheckInRow extends StatelessWidget {
  final Map<String, dynamic> checkIn;
  const _RecentCheckInRow({required this.checkIn});

  @override
  Widget build(BuildContext context) {
    final member = checkIn['members'] as Map<String, dynamic>?;
    final firstName = member?['first_name'] as String? ?? '';
    final lastName = member?['last_name'] as String? ?? '';
    final email = member?['email'] as String?;
    final inits = initials(firstName, lastName);
    final method = checkIn['method'] as String? ?? 'manual';
    final checkedAt = checkIn['checked_in_at'] as String?;

    final methodBg = method == 'qr' ? AppTheme.statusNeutralBg : AppTheme.activeBg;
    final methodFg = method == 'qr' ? AppTheme.statusNeutral : AppTheme.inkSoft;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeAgo(checkedAt),
                    style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: methodBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      method.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: methodFg,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16),
      ],
    );
  }
}
