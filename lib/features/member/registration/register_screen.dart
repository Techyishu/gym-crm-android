import 'dart:convert';
import 'dart:typed_data';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/blood_group_field.dart';
import '../../../shared/widgets/redesign.dart' show BoxField;

/// Public self-registration form behind the gym's QR / link
/// (`/register/<token>`). Needs no login: it reads the form through
/// `get_registration_form` and files a pending request through
/// `submit_member_registration`. Nothing is added to the gym until staff
/// review it in the app.
class MemberRegisterScreen extends StatefulWidget {
  final String token;
  const MemberRegisterScreen({super.key, required this.token});

  @override
  State<MemberRegisterScreen> createState() => _MemberRegisterScreenState();
}

class _MemberRegisterScreenState extends State<MemberRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  bool _loading = true;
  String? _blockedReason; // invalid | disabled | expired | load
  String _gymName = '';
  String _dial = '91';
  bool _showPrices = true;
  List<Map<String, dynamic>> _plans = const [];

  String? _dob;
  String? _blood;
  String? _planId;
  bool _consent = false;
  bool _more = false;
  bool _planMissing = false;
  bool _consentMissing = false;
  bool _sending = false;
  bool _done = false;
  Uint8List? _photo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _phoneCtrl,
      _emailCtrl,
      _emergencyNameCtrl,
      _emergencyPhoneCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _blockedReason = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'get_registration_form',
        params: {'p_token': widget.token},
      );
      if (res is! Map) throw Exception('bad response');
      if (res['ok'] != true) {
        _blockedReason = '${res['reason']}';
      } else {
        final gym = res['gym'] as Map;
        final country = gym['country'] as String?;
        // Same gym-level setters the signed-in app uses, so the dial code and
        // currency on this page match what the owner sees.
        setGymCountry(country);
        setCurrency(gym['currency'] as String?);
        _gymName = '${gym['name'] ?? ''}';
        _dial = Country.tryParse(country ?? '')?.phoneCode ?? '91';
        _showPrices = res['show_prices'] != false;
        _plans = ((res['plans'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
        if (_plans.length == 1) _planId = _plans.first['id'] as String?;
      }
    } catch (e) {
      debugPrint('[GymCRM] registration form load failed: $e');
      _blockedReason = 'load';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob != null
          ? DateTime.parse(_dob!)
          : DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && mounted) {
      setState(() => _dob = picked.toIso8601String().split('T')[0]);
    }
  }

  String _reasonMessage(AppLocalizations l, String reason) {
    switch (reason) {
      case 'invalid':
        return l.regErrInvalid;
      case 'disabled':
        return l.regErrDisabled;
      case 'expired':
        return l.regErrExpired;
      case 'rate_limited':
      case 'too_many':
        return l.regErrBusy;
      case 'photo_too_large':
      case 'invalid_photo':
        return l.regErrPhoto;
      default:
        return l.regErrGeneric;
    }
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final formOk = _formKey.currentState!.validate();
    final planMissing = _plans.isNotEmpty && _planId == null;
    setState(() {
      _planMissing = planMissing;
      _consentMissing = !_consent;
    });
    if (!formOk || planMissing || !_consent) return;

    setState(() => _sending = true);
    String? error;
    try {
      final res = await Supabase.instance.client.rpc(
        'submit_member_registration',
        params: {
          'p_token': widget.token,
          'p_data': {
            'first_name': _firstName,
            'last_name': _lastName,
            'phone': phoneWithCountryCode(_phoneCtrl.text, dialCode: _dial),
            'email': _emailCtrl.text.trim(),
            'dob': _dob,
            'blood_group': _blood,
            'emergency_contact_name': _emergencyNameCtrl.text.trim(),
            'emergency_contact_phone': phoneWithCountryCode(
              _emergencyPhoneCtrl.text,
              dialCode: _dial,
            ),
            'plan_id': _planId,
          },
          'p_photo': _photo == null ? null : base64Encode(_photo!),
        },
      );
      if (res is Map && res['ok'] == true) {
        if (mounted) setState(() => _done = true);
      } else {
        error = _reasonMessage(l, res is Map ? '${res['reason']}' : '');
        if (res is Map &&
            const {'invalid', 'disabled', 'expired'}.contains(res['reason'])) {
          if (mounted) {
            setState(() {
              _blockedReason = '${res['reason']}';
              _sending = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('[GymCRM] registration submit failed: $e');
      error = l.regErrGeneric;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  // "Rohit Sharma" → ("Rohit", "Sharma"); one word keeps last name empty.
  List<String> get _nameParts => _nameCtrl.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  String get _firstName => _nameParts.isEmpty ? '' : _nameParts.first;
  String get _lastName =>
      _nameParts.length < 2 ? '' : _nameParts.sublist(1).join(' ');

  void _another() {
    _formKey.currentState?.reset();
    for (final c in [
      _nameCtrl,
      _phoneCtrl,
      _emailCtrl,
      _emergencyNameCtrl,
      _emergencyPhoneCtrl,
    ]) {
      c.clear();
    }
    setState(() {
      _done = false;
      _sending = false;
      _photo = null;
      _dob = null;
      _blood = null;
      _consent = false;
      _more = false;
      _planId = _plans.length == 1 ? _plans.first['id'] as String? : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l = context.l10n;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_blockedReason != null) {
      final msg = switch (_blockedReason) {
        'disabled' => l.regErrDisabled,
        'expired' => l.regErrExpired,
        'load' => l.regErrLoad,
        _ => l.regErrInvalid,
      };
      return _centered(
        icon: Icons.info_outline,
        title: msg,
        action: _blockedReason == 'load'
            ? OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _load,
                child: Text(l.regRetry),
              )
            : null,
      );
    }
    if (_done) {
      return _centered(
        icon: Icons.check_circle,
        iconColor: AppTheme.accent,
        title: l.regSentTitle,
        body: l.regSentBody(_gymName),
        action: TextButton(onPressed: _another, child: Text(l.regAnother)),
      );
    }
    return _form(context, l);
  }

  Widget _centered({
    required IconData icon,
    Color? iconColor,
    required String title,
    String? body,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: iconColor ?? AppTheme.inkSoft),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, color: AppTheme.inkSoft),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    );
  }

  Widget _form(BuildContext context, AppLocalizations l) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text(
            l.regTitle(_gymName),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.regSubtitle(_gymName),
            style: const TextStyle(fontSize: 14.5, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _photo != null
                      ? Image.memory(_photo!, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              AppIcons.photoCamera,
                              size: 22,
                              color: AppTheme.inkSoft,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.regPhoto,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.inkSoft,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: l.fullName,
                        counterText: '',
                      ),
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? l.required : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _phoneCtrl,
                      maxLength: 20,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 4),
                          child: Text(
                            '+$_dial',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                        ),
                        hintText: l.mobileNumber,
                        counterText: '',
                      ),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? l.required
                          : validateOptionalPhone(v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BoxField(
                  label: l.regDob,
                  value: _dob != null
                      ? formatDateFromString(_dob)
                      : l.regDobNotSet,
                  onTap: _pickDob,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MemberBloodGroupField(
                  value: _blood,
                  onChanged: (v) => setState(() => _blood = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_more)
            GestureDetector(
              onTap: () => setState(() => _more = true),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  const Icon(
                    AppIcons.addCircle,
                    size: 20,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.regMoreDetails,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            TextFormField(
              controller: _emailCtrl,
              maxLength: 120,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l.email,
                counterText: '',
              ),
              validator: validateOptionalEmail,
            ),
            const SizedBox(height: 14),
            Text(l.emergencyContact, style: AppTheme.kicker),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emergencyNameCtrl,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l.name,
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emergencyPhoneCtrl,
              maxLength: 20,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l.mobileNumber,
                counterText: '',
              ),
              validator: validateOptionalPhone,
            ),
          ],
          if (_plans.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(l.regPlanHeading, style: AppTheme.kicker),
            const SizedBox(height: 8),
            for (final p in _plans) _planCard(l, p),
            if (_planMissing)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.regPlanRequired,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.statusDanger,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 18),
          InkWell(
            onTap: () => setState(() => _consent = !_consent),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      l.regConsent(_gymName),
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_consentMissing && !_consent)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                l.regConsentRequired,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.statusDanger,
                ),
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(l.regSubmit),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(AppLocalizations l, Map<String, dynamic> p) {
    final id = p['id'] as String;
    final selected = _planId == id;
    final price = p['price'] as num?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _planId = id;
          _planMissing = false;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.08)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? AppTheme.accent : AppTheme.inkHint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['name'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                    Text(
                      _intervalLabel(l, p),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showPrices && price != null)
                Text(
                  formatCurrency(price.toDouble()),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _intervalLabel(AppLocalizations l, Map<String, dynamic> p) {
    final days = p['billing_interval_days'] as int?;
    if (days != null) return l.regDays(days);
    final months =
        p['billing_interval_months'] as int? ??
        const {
          'monthly': 1,
          'quarterly': 3,
          'biannual': 6,
          'annual': 12,
        }[p['billing_interval']] ??
        1;
    return l.regMonths(months);
  }
}
