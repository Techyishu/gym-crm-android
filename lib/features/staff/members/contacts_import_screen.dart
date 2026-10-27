import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';
import 'members_screen.dart' show showAddMemberSheet;

/// "Add from phone contacts": pick several contacts, then hand them to the
/// import flow (preview → optional plan → import) as name + phone rows.
/// Nothing leaves the phone until the owner taps Add.
class ContactsImportScreen extends StatefulWidget {
  const ContactsImportScreen({super.key});

  @override
  State<ContactsImportScreen> createState() => _ContactsImportScreenState();
}

class _ContactsImportScreenState extends State<ContactsImportScreen> {
  List<Contact>? _contacts;
  String? _error;
  final _picked = <String>{};
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        setState(() => _error = context.l10n.contactsPermissionDenied);
        return;
      }
      final all = await FlutterContacts.getContacts(withProperties: true);
      setState(
        () =>
            _contacts = all.where((c) => c.phones.isNotEmpty).toList()
              ..sort((a, b) => a.displayName.compareTo(b.displayName)),
      );
    } on MissingPluginException {
      // Native plugin: an over-the-air patch can't add it.
      setState(() => _error = context.l10n.contactsNeedsUpdate);
    } catch (_) {
      setState(() => _error = context.l10n.contactsLoadFailed);
    }
  }

  // Each picked contact opens the normal Add member form, prefilled, so the
  // owner picks the plan and can record a payment — a bulk import can't.
  Future<void> _next() async {
    final queue = <(String, String)>[
      for (final c in _contacts ?? const <Contact>[])
        if (_picked.contains(c.id))
          (c.displayName.trim(), c.phones.first.number),
    ];
    await showAddMemberSheet(context, queue: queue);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final q = _q.toLowerCase();
    final list = (_contacts ?? const <Contact>[])
        .where(
          (c) =>
              q.isEmpty ||
              c.displayName.toLowerCase().contains(q) ||
              c.phones.any((p) => p.number.contains(q)),
        )
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l.addFromContacts)),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: AppTheme.inkSoft),
                ),
              ),
            )
          : _contacts == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: l.searchNameOrPhone,
                      prefixIcon: const Icon(AppIcons.search, size: 20),
                    ),
                    onChanged: (v) => setState(() => _q = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final on = _picked.contains(c.id);
                      return CheckboxListTile(
                        value: on,
                        activeColor: AppTheme.accent,
                        title: Text(
                          c.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(c.phones.first.number),
                        onChanged: (v) => setState(
                          () => v == true
                              ? _picked.add(c.id)
                              : _picked.remove(c.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _next,
                    child: Text(l.addNMembers(_picked.length)),
                  ),
                ),
              ),
            ),
    );
  }
}
