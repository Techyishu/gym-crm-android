import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';

/// Where the public registration form is served (the Flutter web app).
const kRegistrationBaseUrl = 'https://dashboard.gymcrm.in';

String registrationLink(String token) => '$kRegistrationBaseUrl/register/$token';

/// Turns registration on (keeping a still-valid link, otherwise minting one
/// with no expiry so a printed QR keeps working) and opens the share sheet.
/// Used by the Home card in both its states.
Future<void> enableAndShowRegistration(
  BuildContext context,
  WidgetRef ref, {
  required String gymName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  String? token;
  try {
    final gymId = await ref.read(gymIdProvider.future);
    final res = await Supabase.instance.client.rpc(
      'enable_member_registration',
      params: {'p_gym_id': gymId},
    );
    token = res as String?;
  } catch (e) {
    debugPrint('[GymCRM] enable registration failed: $e');
  }
  if (token == null || token.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not turn on registration. Please try again.'),
      ),
    );
    return;
  }
  // The Home card reads the gym row from here; refresh so it flips to "on".
  ref.invalidate(staffProfileProvider);
  if (!context.mounted) return;
  await showAdaptiveSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RegistrationShareSheet(
      gymName: gymName,
      link: registrationLink(token!),
    ),
  );
}

class _RegistrationShareSheet extends ConsumerStatefulWidget {
  final String gymName;
  final String link;
  const _RegistrationShareSheet({required this.gymName, required this.link});

  @override
  ConsumerState<_RegistrationShareSheet> createState() =>
      _RegistrationShareSheetState();
}

class _RegistrationShareSheetState
    extends ConsumerState<_RegistrationShareSheet> {
  bool _busy = false;

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      'Join ${widget.gymName}: register yourself here and the gym will '
      'confirm your membership.\n${widget.link}',
      subject: 'Join ${widget.gymName}',
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  Future<void> _poster() async {
    setState(() => _busy = true);
    try {
      final bytes = await _buildPoster(widget.gymName, widget.link);
      await Printing.sharePdf(bytes: bytes, filename: 'member-registration.pdf');
    } catch (e) {
      debugPrint('[GymCRM] registration poster failed: $e');
      if (mounted) _toast('Could not create the poster. Please try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _turnOff() async {
    setState(() => _busy = true);
    try {
      final gymId = await ref.read(gymIdProvider.future);
      await Supabase.instance.client
          .from('gyms')
          .update({'registration_enabled': false})
          .eq('id', gymId);
      ref.invalidate(staffProfileProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[GymCRM] turn off registration failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        _toast('Could not turn it off. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Member registration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Members scan this, fill in their own details and pick a plan. '
              'You review each one before they are added.',
              style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: QrImageView(
                  data: widget.link,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: AppTheme.cardDecoration(),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.link,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.link));
                      _toast('Link copied');
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Text(
                        'Copy',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _busy ? null : _share,
              child: const Text('Share on WhatsApp'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _poster,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Print poster for your desk'),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _turnOff,
                child: const Text(
                  'Turn off registration',
                  style: TextStyle(color: AppTheme.inkSoft),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A4 poster: gym name, a short instruction, and the QR. English only —
/// Manrope has no Devanagari, and a gym name in another script would blank.
Future<Uint8List> _buildPoster(String gymName, String link) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Manrope_400Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Manrope_700Bold.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      build: (_) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            gymName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 34),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Become a member',
            style: pw.TextStyle(font: bold, fontSize: 26),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Scan with your phone camera and fill in your details.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: regular, fontSize: 16),
          ),
          pw.SizedBox(height: 36),
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 2),
              borderRadius: pw.BorderRadius.circular(16),
            ),
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: link,
              width: 280,
              height: 280,
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(link, style: pw.TextStyle(font: regular, fontSize: 11)),
        ],
      ),
    ),
  );
  return doc.save();
}
