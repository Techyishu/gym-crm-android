import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'redesign.dart';

/// Pick several members at once — used to copy one plan onto a group.
///
/// Returns the chosen rows, or null if the sheet was dismissed. Search filters
/// the list but never clears the ticks: a trainer picking six people out of two
/// hundred types a name, ticks, clears the box, types the next one.
Future<List<Map<String, dynamic>>?> showMemberMultiPicker({
  required BuildContext context,
  required List<Map<String, dynamic>> members,
  required String title,
  required String subtitle,
  required String confirmLabel,
}) => showAdaptiveSheet<List<Map<String, dynamic>>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  maxHeight: 640,
  builder: (_) => _MemberMultiPicker(
    members: members,
    title: title,
    subtitle: subtitle,
    confirmLabel: confirmLabel,
  ),
);

/// The on-card entry point to [showMemberMultiPicker].
///
/// Says "Copy to others" rather than "Assign": the plan screens already use
/// "Assign" for giving a member their first plan, and one word doing two jobs
/// is exactly what confuses someone at the front desk.
class CopyToOthersButton extends StatelessWidget {
  final VoidCallback onTap;
  const CopyToOthersButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.accentSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(AppIcons.groups, size: 13, color: AppTheme.accent),
            SizedBox(width: 5),
            Text(
              'Copy to others',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Offered right after a plan is saved, while the trainer is still thinking
/// about who else needs it — the moment the intent actually exists, rather
/// than relying on them coming back to the card later.
Future<bool> askToCopyToOthers(BuildContext context, String memberName) async {
  final answer = await showAdaptiveSheet<bool>(
    context: context,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(sheetContext).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: 'Plan saved',
            subtitle:
                'Saved for $memberName. Do other members train on the same plan?',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(sheetContext, true),
              child: const Text('Copy to others'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text(
                'Not now',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return answer == true;
}

class _MemberMultiPicker extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final String title;
  final String subtitle;
  final String confirmLabel;

  const _MemberMultiPicker({
    required this.members,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
  });

  @override
  State<_MemberMultiPicker> createState() => _MemberMultiPickerState();
}

class _MemberMultiPickerState extends State<_MemberMultiPicker> {
  final _selected = <String>{};
  String _query = '';

  static String _name(Map<String, dynamic> m) =>
      '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.members
        : widget.members
              .where((m) => _name(m).toLowerCase().contains(q))
              .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: widget.title, subtitle: widget.subtitle),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search members',
              prefixIcon: Icon(AppIcons.search, size: 20),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No members match that search.',
                      style: TextStyle(color: AppTheme.inkHint),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final m = filtered[i];
                      final id = m['id'] as String;
                      final checked = _selected.contains(id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) => setState(
                          () => v == true
                              ? _selected.add(id)
                              : _selected.remove(id),
                        ),
                        activeColor: AppTheme.accent,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          _name(m),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.ink,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              // Disabled until something is ticked: assigning to nobody is
              // always a mistake, not a choice.
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      widget.members
                          .where((m) => _selected.contains(m['id']))
                          .toList(),
                    ),
              child: Text(
                _selected.isEmpty
                    ? widget.confirmLabel
                    : '${widget.confirmLabel} (${_selected.length})',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
