import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

class InvoiceSettingsScreen extends ConsumerStatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  ConsumerState<InvoiceSettingsScreen> createState() =>
      _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends ConsumerState<InvoiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _gymName = TextEditingController();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _gstin = TextEditingController();
  final _prefix = TextEditingController(text: 'INV');
  final _numberPadding = TextEditingController(text: '6');
  final _gstPercent = TextEditingController(text: '0');
  final _refundPolicy = TextEditingController();
  final _terms = TextEditingController();
  String? _logoUrl;
  XFile? _logo;
  bool _showInvoiceDate = true;
  bool _showGeneratedDate = true;
  bool _showMembershipId = true;
  bool _showAdmissionFee = true;
  bool _showDiscount = true;
  bool _showGstBreakup = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// A rate the owner meant to charge — anything above 0.
  bool get _gstRateEntered =>
      (double.tryParse(_gstPercent.text.trim()) ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final controller in [
      _gymName,
      _ownerName,
      _email,
      _phone,
      _address,
      _gstin,
      _prefix,
      _numberPadding,
      _gstPercent,
      _refundPolicy,
      _terms,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final raw = await ref
          .read(supabaseProvider)
          .rpc('get_invoice_settings', params: {'p_gym_id': gymId});
      final settings = Map<String, dynamic>.from(raw as Map? ?? const {});
      _gymName.text = settings['gym_name'] as String? ?? '';
      _ownerName.text = settings['owner_name'] as String? ?? '';
      _email.text = settings['contact_email'] as String? ?? '';
      _phone.text = settings['contact_phone'] as String? ?? '';
      _address.text = settings['address'] as String? ?? '';
      _gstin.text = settings['gstin'] as String? ?? '';
      _prefix.text = settings['invoice_prefix'] as String? ?? 'INV';
      _numberPadding.text = '${(settings['number_padding'] as num?) ?? 6}';
      _gstPercent.text = '${(settings['gst_percent'] as num?) ?? 0}';
      _refundPolicy.text = settings['refund_policy'] as String? ?? '';
      _terms.text = settings['terms_and_conditions'] as String? ?? '';
      _logoUrl = settings['logo_url'] as String?;
      _showInvoiceDate = settings['show_invoice_date'] != false;
      _showGeneratedDate = settings['show_generated_date'] != false;
      _showMembershipId = settings['show_membership_id'] != false;
      _showAdmissionFee = settings['show_admission_fee'] != false;
      _showDiscount = settings['show_discount'] != false;
      _showGstBreakup = settings['show_gst_breakup'] == true;
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _pickLogo() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 90,
      );
      if (picked != null && mounted) setState(() => _logo = picked);
    } on PlatformException catch (error) {
      if (mounted && error.code != 'already_active') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the image picker.')),
        );
      }
    }
  }

  Future<String?> _uploadLogo(String gymId) async {
    if (_logo == null) return _logoUrl;
    final extension = _logo!.name.split('.').last.toLowerCase();
    final safeExtension = {'png', 'webp', 'jpg', 'jpeg'}.contains(extension)
        ? extension
        : 'jpg';
    final mime = safeExtension == 'png'
        ? 'image/png'
        : safeExtension == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    final path = '$gymId/invoice-logo.$safeExtension';
    await Supabase.instance.client.storage
        .from('gym-logos')
        .uploadBinary(
          path,
          await _logo!.readAsBytes(),
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    final url = Supabase.instance.client.storage
        .from('gym-logos')
        .getPublicUrl(path);
    return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final logoUrl = await _uploadLogo(gymId);
      await ref
          .read(supabaseProvider)
          .rpc(
            'update_invoice_settings',
            params: {
              'p_gym_id': gymId,
              'p_settings': {
                'gym_name': _gymName.text.trim(),
                'logo_url': logoUrl,
                'owner_name': _ownerName.text.trim(),
                'contact_email': _email.text.trim(),
                'contact_phone': _phone.text.trim(),
                'address': _address.text.trim(),
                'gstin': _gstin.text.trim().toUpperCase(),
                'invoice_prefix': _prefix.text.trim().toUpperCase(),
                'number_padding': int.tryParse(_numberPadding.text.trim()) ?? 6,
                'show_invoice_date': _showInvoiceDate,
                'show_generated_date': _showGeneratedDate,
                'show_membership_id': _showMembershipId,
                'show_admission_fee': _showAdmissionFee,
                'show_discount': _showDiscount,
                'show_gst_breakup': _showGstBreakup,
                'gst_percent': double.tryParse(_gstPercent.text.trim()) ?? 0,
                'refund_policy': _refundPolicy.text.trim(),
                'terms_and_conditions': _terms.text.trim(),
              },
            },
          );
      _logoUrl = logoUrl;
      _logo = null;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invoice settings saved')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Invoice settings')),
      body: ResponsiveContent(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _gymName.text.isEmpty
            ? ErrorState(what: 'invoice settings', onRetry: _load)
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 14),
                    ],
                    const Text('Invoice header', style: AppTheme.sectionTitle),
                    const SizedBox(height: 10),
                    _logoPicker(),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _gymName,
                      decoration: const InputDecoration(labelText: 'Gym name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Gym name is required'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _ownerName,
                      decoration: const InputDecoration(
                        labelText: 'Owner / contact name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Contact email',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact phone',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _address,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _gstin,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'GSTIN'),
                    ),
                    const SizedBox(height: 26),
                    const Text('Numbering & tax', style: AppTheme.sectionTitle),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _prefix,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Invoice prefix',
                        helperText: 'Example: INV or GYM-INV',
                      ),
                      validator: (value) =>
                          RegExp(
                            r'^[A-Za-z0-9][A-Za-z0-9/-]{0,15}$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Use letters, numbers, /, or - (max 16)',
                    ),
                    const SizedBox(height: 10),
                    // GST is two settings that only work together: a rate above
                    // zero AND the breakup switch. They used to sit in separate
                    // sections, so entering 18% with the switch off silently
                    // produced no tax at all. Keeping them adjacent — and
                    // validating each against the other — is what makes that
                    // impossible to do by accident.
                    TextFormField(
                      controller: _gstPercent,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'GST rate (%)',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final number = double.tryParse(value?.trim() ?? '');
                        if (number == null || number < 0 || number > 100) {
                          return 'Enter a rate from 0 to 100';
                        }
                        if (_showGstBreakup && number == 0) {
                          return 'Enter a rate above 0, or turn GST breakup off';
                        }
                        return null;
                      },
                    ),
                    _switch('GST breakup (CGST + SGST)', _showGstBreakup, (
                      value,
                    ) {
                      setState(() => _showGstBreakup = value);
                      // Surface "rate above 0" the moment the switch goes on,
                      // rather than holding it back until they hit Save.
                      if (value) _formKey.currentState?.validate();
                    }),
                    if (_gstRateEntered && !_showGstBreakup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'This rate is saved but not applied. Turn on GST '
                          'breakup to add GST to new invoices.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.statusWarn,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _numberPadding,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Invoice number digits',
                        helperText: '6 produces INV-000001',
                      ),
                      validator: (value) {
                        final number = int.tryParse(value?.trim() ?? '');
                        return number == null || number < 3 || number > 10
                            ? 'Enter 3 to 10 digits'
                            : null;
                      },
                    ),
                    const SizedBox(height: 22),
                    const Text('Fields shown', style: AppTheme.sectionTitle),
                    const SizedBox(height: 6),
                    _switch(
                      'Invoice date',
                      _showInvoiceDate,
                      (value) => setState(() => _showInvoiceDate = value),
                    ),
                    _switch(
                      'Generated date',
                      _showGeneratedDate,
                      (value) => setState(() => _showGeneratedDate = value),
                    ),
                    _switch(
                      'Membership ID',
                      _showMembershipId,
                      (value) => setState(() => _showMembershipId = value),
                    ),
                    _switch(
                      'Admission / joining fee',
                      _showAdmissionFee,
                      (value) => setState(() => _showAdmissionFee = value),
                    ),
                    _switch(
                      'Discount',
                      _showDiscount,
                      (value) => setState(() => _showDiscount = value),
                    ),
                    const SizedBox(height: 22),
                    const Text('Policy & terms', style: AppTheme.sectionTitle),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _refundPolicy,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Refund policy',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _terms,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Terms & conditions',
                      ),
                    ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _loading || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save invoice settings'),
        ),
      ),
    );
  }

  Widget _logoPicker() => Material(
    color: AppTheme.surface,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: _pickLogo,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _logo != null
                  ? const Icon(AppIcons.image)
                  : _logoUrl?.isNotEmpty == true
                  ? Image.network(
                      _logoUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(AppIcons.brokenImage),
                    )
                  : const Icon(AppIcons.addPhoto),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _logo == null ? 'Invoice logo' : _logo!.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Tap to choose PNG, JPG, or WebP',
                    style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                  ),
                ],
              ),
            ),
            const Icon(AppIcons.chevronRight),
          ],
        ),
      ),
    ),
  );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        value: value,
        onChanged: onChanged,
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.statusDangerBg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(message, style: const TextStyle(color: AppTheme.statusDanger)),
  );
}

String _friendlyError(Object error) {
  final text = '$error';
  if (text.contains('permission_denied')) {
    return "You don't have permission to change invoice settings.";
  }
  if (text.contains('invalid_invoice_prefix')) {
    return 'The invoice prefix is not valid.';
  }
  return 'Could not save invoice settings. Please try again.';
}
