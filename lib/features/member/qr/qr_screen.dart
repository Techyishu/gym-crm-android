import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

/// Outcome of a scan, shown on a confirmation screen that replaces the camera.
class _ScanOutcome {
  final bool success; // green — a fresh check-in was recorded
  final bool already; // amber — already checked in today
  final String title;
  final String? subtitle;
  const _ScanOutcome({
    required this.success,
    this.already = false,
    required this.title,
    this.subtitle,
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
  final MobileScannerController _scanner = MobileScannerController();
  bool _processing = false;
  _ScanOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
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
    await _scanner.stop();

    final token = _extractToken(raw);
    if (token == null) {
      setState(() => _outcome = const _ScanOutcome(
            success: false,
            title: 'Not a gym QR code',
            subtitle: 'Point the camera at your gym’s check-in QR code.',
          ));
      return;
    }

    setState(() => _processing = true);
    try {
      final res = await Supabase.instance.client
          .rpc('self_checkin', params: {'p_token': token});
      final map = (res as Map).cast<String, dynamic>();
      final member = (map['member'] as Map?)?.cast<String, dynamic>();
      final name = member != null
          ? '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim()
          : '';
      final gym = map['gym_name'] as String?;

      if (map['ok'] == true) {
        setState(() => _outcome = _ScanOutcome(
              success: true,
              title: name.isNotEmpty ? 'Welcome, $name!' : 'Checked in!',
              subtitle: gym != null ? 'Checked in at $gym' : 'Check-in recorded',
            ));
      } else if (map['already'] == true) {
        setState(() => _outcome = _ScanOutcome(
              success: false,
              already: true,
              title: 'Already checked in today',
              subtitle: gym != null
                  ? 'You’re all set at $gym. Come back tomorrow!'
                  : 'You’ve already checked in today.',
            ));
      } else {
        setState(() => _outcome = _ScanOutcome(
              success: false,
              title: map['error'] as String? ?? 'Check-in failed',
              subtitle: map['reason'] as String?,
            ));
      }
    } catch (e) {
      setState(() => _outcome = _ScanOutcome(
            success: false,
            title: 'Something went wrong',
            subtitle: '$e',
          ));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _scanAgain() async {
    setState(() => _outcome = null);
    await _scanner.start();
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
          tabs: const [Tab(text: 'My QR Code'), Tab(text: 'Scan Gym QR')],
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
          child: Text('Could not load your QR code',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
      ),
      data: (m) {
        final memberId = m?['id'] as String? ?? '';
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
                      if (memberId.isNotEmpty)
                        QrImageView(
                          data: memberId,
                          version: QrVersions.auto,
                          size: 200,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppTheme.textPrimary,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppTheme.textPrimary,
                          ),
                        )
                      else
                        const SizedBox(
                          width: 200,
                          height: 200,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Scan to Check In',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Show this QR to gym staff at the front desk',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (memberId.isNotEmpty) ...[
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
                              memberId,
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
                    'Tap to copy Member ID',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ],
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
              MobileScanner(
                controller: _scanner,
                onDetect: (capture) {
                  final barcode = capture.barcodes.firstOrNull;
                  if (barcode?.rawValue != null) {
                    _handleScan(barcode!.rawValue!);
                  }
                },
              ),
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
    if (outcome.success) {
      bg = AppTheme.statusActiveBg;
      fg = AppTheme.statusActive;
      icon = Icons.check_circle_outline;
    } else if (outcome.already) {
      bg = AppTheme.statusWarnBg;
      fg = AppTheme.statusWarn;
      icon = Icons.info_outline;
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
              const SizedBox(height: 8),
              Text(
                outcome.subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppTheme.inkHint),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => onScanAgain(),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.ink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: const Text('Scan again',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
