import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';

/// Blood group as a menu rather than a free-text box: eight valid values, and
/// a typo here is worse than a blank — someone reading it in an emergency has
/// to be able to trust it. Optional by design (DPDP: health data, collected
/// only for that emergency purpose).
class MemberBloodGroupField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const MemberBloodGroupField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      onSelected: onChanged,
      // Default is a "Show menu" tooltip that hangs over the field below it.
      tooltip: '',
      itemBuilder: (_) => [
        const PopupMenuItem<String?>(value: null, child: Text('Not set')),
        for (final g in groups)
          PopupMenuItem<String?>(value: g, child: Text(g)),
      ],
      // Deliberately not BoxField: its own GestureDetector is deeper in the
      // tree than the one PopupMenuButton wraps around this child, so it wins
      // the tap and the menu never opens. Same box, no gesture of its own.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Blood group',
                        style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value ?? 'Not set',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  AppIcons.expandMore,
                  size: 16,
                  color: AppTheme.inkHint,
                ),
              ],
            ),
          ),
          // The purpose note lives under the box, not in the label: at half
          // width the label truncated to "Blood group · for ...", which said
          // nothing. Only while unset — once filled in, the value is the point.
          if (value == null) ...[
            const SizedBox(height: 4),
            const Text(
              'Kept for emergencies',
              style: TextStyle(fontSize: 11, color: AppTheme.inkHint),
            ),
          ],
        ],
      ),
    );
  }
}
