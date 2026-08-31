import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

/// Outcome of a scan, shown on a confirmation screen that replaces the camera.
class _ScanOutcome {
  final bool success;
  final bool checkout;
  final String title;
  final String? subtitle;
  final String? checkedInAt;
  final String? checkedOutAt;
  const _ScanOutcome({
    required this.success,
    this.checkout = false,
    required this.title,
    this.subtitle,
    this.checkedInAt,
    this.checkedOutAt,
  });
}

class MemberQrScreen extends ConsumerStatefulWidget {
  const MemberQrScreen({super.key});

  @override
  ConsumerState<MemberQrScreen> createState() => _MemberQrScreenState();
}

class _MemberQrScreenState extends ConsumerState<MemberQrScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  // autoStart is off — the tab listener below owns start()/stop(), and
  // leaving autoStart on races with it (mobile_scanner throws instead of
  // queuing when start() is called while a previous start() is still
  // resolving).
  final MobileScannerController _scanner = MobileScannerController(
    autoStart: false,
  );
  StreamSubscription<BarcodeCapture>? _barcodeSub;
  bool _processing = false;
  _ScanOutcome? _outcome;

  // Capture target for "Save to phone" — the QR card, not the whole screen.
  final _qrCaptureKey = GlobalKey();
  bool _savingQr = false;

  Future<void> _saveQrToGallery(String memberName) async {
    setState(() => _savingQr = true);
    try {
      final boundary =
          _qrCaptureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return;
      final safeName = memberName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
      await Gal.putImageBytes(
        bytes,
        album: 'GymCRM',
        name: 'member_qr_$safeName',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved to gallery')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the QR code. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingQr = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
    _barcodeSub = _scanner.barcodes.listen((capture) {
      final barcode = capture.barcodes.firstOrNull;
      if (barcode?.rawValue != null) {
        _handleScan(barcode!.rawValue!);
      }
    });
  }

  // Run the camera only while the Scan tab is active and no result is showing.
  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 1 && _outcome == null) {
      _scanner.start().catchError((_) {});
    } else {
      _scanner.stop().catchError((_) {});
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _barcodeSub?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  /// Pulls the check-in token out of a scanned gym QR. Accepts the full
  /// `https://gymcrm.in/c/{token}` URL the web app prints, or a bare token.
  String? _extractToken(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    try {
      final uri = Uri.parse(value);
      if (uri.pathSegments.isNotEmpty) {
        final segs = uri.pathSegments;
        final idx = segs.indexOf('c');
        if (idx != -1 && idx + 1 < segs.length) return segs[idx + 1];
      }
    } catch (e) {
      debugPrint('[GymCRM] QR URL parse (not a URL): $e');
    }
    if (RegExp(r'^[0-9a-fA-F-]{20,}$').hasMatch(value)) return value;
    return null;
  }

  Future<void> _handleScan(String raw) async {
    // Ignore further frames once we're processing or already showing a result.
    if (_processing || _outcome != null) return;

    // Freeze the camera immediately so it can't fire again on the next frame.
    await _scanner.stop().catchError((_) {});

    final token = _extractToken(raw);
    if (token == null) {
      setState(
        () => _outcome = const _ScanOutcome(
          success: false,
          title: 'Not a gym QR code',
          subtitle: "Point the camera at your gym's check-in QR code.",
        ),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      final res = await Supabase.instance.client.rpc(
        'self_checkin',
        params: {'p_token': token},
      );
      final map = (res as Map).cast<String, dynamic>();
      final member = (map['member'] as Map?)?.cast<String, dynamic>();
      final name = member != null
          ? '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim()
          : '';
      final gym = map['gym_name'] as String?;

      if (map['ok'] == true) {
        final action = map['action'] as String? ?? 'checkin';
        final checkedInAt = map['checked_in_at'] as String?;
        final checkedOutAt = map['checked_out_at'] as String?;
        if (action == 'checkout') {
          setState(
            () => _outcome = _ScanOutcome(
              success: true,
              checkout: true,
              title: name.isNotEmpty ? 'See you, $name!' : 'Checked out!',
              subtitle: gym,
              checkedInAt: checkedInAt,
              checkedOutAt: checkedOutAt,
            ),
          );
        } else {
          setState(
            () => _outcome = _ScanOutcome(
              success: true,
              title: name.isNotEmpty ? 'Welcome, $name!' : 'Checked in!',
              subtitle: gym,
              checkedInAt: checkedInAt,
            ),
          );
        }
      } else {
        setState(
          () => _outcome = _ScanOutcome(
            success: false,
            title: map['error'] as String? ?? 'Check-in failed',
            subtitle: map['reason'] as String?,
          ),
        );
      }
    } catch (e) {
      setState(
        () => _outcome = _ScanOutcome(
          success: false,
          title: 'Something went wrong',
          subtitle: '$e',
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _scanAgain() async {
    setState(() => _outcome = null);
    await _scanner.start().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Check In'),
        bottom: TabBar(
          controller: _tabs,
          onTap: (_) {
            // Leaving the scan tab: drop any result so returning starts fresh.
            if (_outcome != null) _scanAgain();
          },
          tabs: const [
            Tab(text: 'My QR Code'),
            Tab(text: 'Scan Gym QR'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildMyQrTab(), _buildScanTab()],
      ),
    );
  }

  // ── My QR tab ───────────────────────────────────────────────────────────────

  Widget _buildMyQrTab() {
    final memberAsync = ref.watch(memberRecordProvider);

    return memberAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Could not load your QR code',
            style: TextStyle(color: AppTheme.onDarkSoft),
          ),
        ),
      ),
      data: (m) {
        final memberId = m?['id'] as String? ?? '';
        final firstName = m?['first_name'] as String? ?? '';
        final lastName = m?['last_name'] as String? ?? '';
        final fullName = '$firstName $lastName'.trim();
        final customId = m?['custom_id'] as String?;
        final memberships = (m?['memberships'] as List?) ?? const [];
        final currentMs = memberships.isNotEmpty
            ? memberships.first as Map<String, dynamic>
            : null;
        final planName =
            (currentMs?['membership_plans'] as Map<String, dynamic>?)?['name']
                as String?;
        final endsAt = currentMs?['ends_at'] as String?;

        final idLine = [
          if (customId != null && customId.isNotEmpty)
            'Member ID $customId'
          else
            'Member',
          if (planName != null && planName.isNotEmpty) planName,
        ].join(' · ');

        return ColoredBox(
          color: AppTheme.darkCard,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Your check-in code',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onDark,
                    ),
                  ),
                  const SizedBox(height: 20),
                  RepaintBoundary(
                    key: _qrCaptureKey,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.onDark,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: memberId.isEmpty
                          ? const SizedBox(
                              width: 220,
                              height: 220,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : QrImageView(
                              data: memberId,
                              version: QrVersions.auto,
                              size: 220,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: AppTheme.darkCard,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: AppTheme.darkCard,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (fullName.isNotEmpty)
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onDark,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    idLine,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.onDarkSoft,
                    ),
                  ),
                  if (endsAt != null && endsAt.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Active till ${formatDateFromString(endsAt)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.onDarkSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (memberId.isNotEmpty)
                    GestureDetector(
                      onTap: _savingQr
                          ? null
                          : () => _saveQrToGallery(
                              fullName.isEmpty ? 'member' : fullName,
                            ),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard2,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _savingQr ? AppIcons.hourglass : AppIcons.iosShare,
                              size: 17,
                              color: AppTheme.onDark,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _savingQr ? 'Saving…' : 'Save to phone',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.onDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (memberId.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: memberId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Member ID copied'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      behavior: HitTestBehavior.opaque,
                      child: const Text(
                        'Tap to copy member ID',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.onDarkSoft,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Scan tab ────────────────────────────────────────────────────────────────

  Widget _buildScanTab() {
    if (_outcome != null) {
      return _ScanResultView(outcome: _outcome!, onScanAgain: _scanAgain);
    }
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(controller: _scanner),
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.accent, width: 2),
                    borderRadius: BorderRadius.circular(16),
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
        const Text(
          'Point camera at the gym check-in QR code',
          style: TextStyle(color: AppTheme.inkHint, fontSize: 14),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Confirmation screen ─────────────────────────────────────────────────────────

class _ScanResultView extends StatelessWidget {
  final _ScanOutcome outcome;
  final Future<void> Function() onScanAgain;
  const _ScanResultView({required this.outcome, required this.onScanAgain});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    if (outcome.checkout) {
      bg = AppTheme.statusWarnBg;
      fg = AppTheme.statusWarn;
      icon = AppIcons.logout;
    } else if (outcome.success) {
      bg = AppTheme.statusActiveBg;
      fg = AppTheme.statusActive;
      icon = AppIcons.checkCircle;
    } else {
      bg = AppTheme.statusDangerBg;
      fg = AppTheme.statusDanger;
      icon = AppIcons.error;
    }

    String fmt(String iso) {
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt == null) return iso;
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour < 12 ? 'AM' : 'PM';
      return '$h:$m $period';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: fg, size: 52),
            ),
            const SizedBox(height: 24),
            Text(
              outcome.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            if (outcome.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                outcome.subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.inkHint),
              ),
            ],
            if (outcome.success) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    if (outcome.checkedInAt != null)
                      _TimeRow(
                        label: 'Checked in',
                        time: fmt(outcome.checkedInAt!),
                        color: AppTheme.statusActive,
                      ),
                    if (outcome.checkedOutAt != null) ...[
                      const SizedBox(height: 8),
                      _TimeRow(
                        label: 'Checked out',
                        time: fmt(outcome.checkedOutAt!),
                        color: AppTheme.statusWarn,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => onScanAgain(),
                icon: const Icon(AppIcons.qrScanner, size: 18),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.ink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: const Text(
                  'Scan again',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  const _TimeRow({
    required this.label,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
        ),
        Text(
          time,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
