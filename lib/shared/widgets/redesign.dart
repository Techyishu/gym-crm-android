import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'member_photo.dart';
import '../../core/theme/app_icons.dart';

/// Shared building blocks for the "calmer, more confident" redesign.
/// Warm neutrals, single orange accent, rounded initials avatars,
/// pill status badges, tabular numbers.

// ── Initials avatar ──────────────────────────────────────────────────────────

/// Tint pairs cycled deterministically by name so a member keeps their color.
const List<(Color, Color)> _avatarTints = [
  (Color(0xFFDDEFE2), Color(0xFF2E7D4F)), // mint / green
  (Color(0xFFF4E8CD), Color(0xFFB07C1F)), // sand / amber
  (Color(0xFFF8DFD7), Color(0xFFC2492F)), // blush / rust
  (Color(0xFFE9E6DD), Color(0xFF6E6A60)), // stone / grey
];

(Color, Color) avatarTintFor(String name) =>
    _avatarTints[name.isEmpty ? 0 : name.codeUnitAt(0) % _avatarTints.length];

String initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? photo; // stored storage path / legacy URL
  final Color? bg;
  final Color? fg;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.photo,
    this.bg,
    this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final (tintBg, tintFg) = avatarTintFor(name);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? tintBg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: fg ?? tintFg,
        ),
      ),
    );
    if (photo == null || photo!.isEmpty) return fallback;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.32),
        child: MemberPhoto(stored: photo, fallback: fallback),
      ),
    );
  }
}

// ── Status pill ──────────────────────────────────────────────────────────────

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    required this.bg,
  });

  factory StatusPill.active({String label = 'Active'}) => StatusPill(
    label: label,
    color: AppTheme.statusActive,
    bg: AppTheme.statusActiveBg,
  );
  factory StatusPill.warn({String label = 'Lapsing'}) => StatusPill(
    label: label,
    color: AppTheme.statusWarn,
    bg: AppTheme.statusWarnBg,
  );
  factory StatusPill.danger({String label = 'Expired'}) => StatusPill(
    label: label,
    color: AppTheme.statusDanger,
    bg: AppTheme.statusDangerBg,
  );
  factory StatusPill.neutral({String label = 'On hold'}) => StatusPill(
    label: label,
    color: AppTheme.statusNeutral,
    bg: AppTheme.statusNeutralBg,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Filter chip (segmented pills with optional count) ────────────────────────

class PillChip extends StatelessWidget {
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback onTap;

  /// Optional tint when unselected (e.g. amber "Lapsing" chip).
  final Color? tintBg;
  final Color? tintFg;

  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.tintBg,
    this.tintFg,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppTheme.ink : (tintBg ?? AppTheme.surface);
    final fg = selected ? Colors.white : (tintFg ?? AppTheme.ink);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            if (count != null)
              Text(
                count!,
                style: AppTheme.numberStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : (tintFg ?? AppTheme.ink),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        const Spacer(),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Light stat tile (Active / Check-ins / Renewals) ──────────────────────────

class StatTileLight extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const StatTileLight({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: AppTheme.numberStyle(fontSize: 21)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card list (white rounded container with divided rows) ────────────────────

class CardList extends StatelessWidget {
  final List<Widget> children;
  const CardList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
    }
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(children: rows),
    );
  }
}

// ── Small pill action button (Remind / Collect / Message) ────────────────────

class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled; // filled orange vs neutral grey
  final Color? color;

  const PillButton({
    super.key,
    required this.label,
    this.onTap,
    this.filled = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? (color ?? AppTheme.accent) : AppTheme.surface2;
    final fg = filled ? Colors.white : AppTheme.ink;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}

// ── Round icon button (call / whatsapp circles) ──────────────────────────────

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? bg;
  final Color? fg;
  final double size;

  const RoundIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.bg,
    this.fg,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg ?? AppTheme.surface2,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size * 0.45, color: fg ?? AppTheme.ink),
      ),
    );
  }
}

// ── Uppercase field label (ADD MEMBER form style) ────────────────────────────

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppTheme.inkSoft,
        ),
      ),
    );
  }
}

// ── Confirm dialog (rounded card, icon in tinted circle, 2-button row) ───────

/// Shows the app's standard confirmation dialog: icon in a tinted circle,
/// title, body text, and a Cancel/destructive button pair. Returns true if
/// the destructive action was confirmed, false/null otherwise.
// ── App dialog shell ──────────────────────────────────────────────────────────
//
// Every dialog in the app (confirm, info, or one with an input field) goes
// through this shell instead of a bare Material `AlertDialog` — same rounded
// surface card, centered icon chip, bold title, and pill-shaped actions, so
// "are you sure?" and "edit this value" prompts all read as the same app
// rather than a mix of custom cards and stock Material dialogs.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  IconData? icon,
  bool danger = false,
  Widget? content,
  // Takes the dialog route's own BuildContext — actions must pop *that*
  // context, not the caller's. showDialog pushes onto the root navigator by
  // default, but the caller's context (e.g. a screen nested inside a
  // go_router shell branch) resolves to a different, nested navigator.
  // Popping via the wrong one closes the underlying screen instead of the
  // dialog.
  required List<Widget> Function(BuildContext dialogContext) actions,
}) {
  final tint = danger ? AppTheme.statusDanger : AppTheme.accent;
  final tintBg = danger ? AppTheme.statusDangerBg : AppTheme.accentSoft;
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final builtActions = actions(ctx);
      return Dialog(
        backgroundColor: AppTheme.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: tintBg,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, size: 26, color: tint),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              if (content != null) ...[const SizedBox(height: 8), content],
              const SizedBox(height: 22),
              Row(
                children: [
                  for (var i = 0; i < builtActions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: builtActions[i]),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Pill button for use inside [showAppDialog]'s `actions`. `filled` gives it
/// a solid [tint] background (primary/destructive action); unfilled reads as
/// the neutral "Cancel" choice.
class DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final Color? tint;
  const DialogButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppTheme.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        decoration: BoxDecoration(
          color: filled ? color : AppTheme.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : AppTheme.ink,
          ),
        ),
      ),
    );
  }
}

Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String cancelLabel = 'Cancel',
  required String confirmLabel,
  IconData icon = AppIcons.error,
  bool danger = true,
}) {
  final tint = danger ? AppTheme.statusDanger : AppTheme.accent;
  return showAppDialog<bool>(
    context,
    title: title,
    icon: icon,
    danger: danger,
    content: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        body,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13.5,
          color: AppTheme.inkSoft,
          height: 1.4,
        ),
      ),
    ),
    actions: (ctx) => [
      DialogButton(label: cancelLabel, onTap: () => Navigator.pop(ctx, false)),
      DialogButton(
        label: confirmLabel,
        filled: true,
        tint: tint,
        onTap: () => Navigator.pop(ctx, true),
      ),
    ],
  );
}

/// Single-button informational dialog — the styled equivalent of an
/// `AlertDialog` with just an "OK". Use when there's nothing to confirm, only
/// something the user needs to acknowledge before continuing.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String body,
  String buttonLabel = 'OK',
  IconData icon = AppIcons.info,
}) {
  return showAppDialog<void>(
    context,
    title: title,
    icon: icon,
    content: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        body,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13.5,
          color: AppTheme.inkSoft,
          height: 1.4,
        ),
      ),
    ),
    actions: (ctx) => [
      DialogButton(
        label: buttonLabel,
        filled: true,
        onTap: () => Navigator.pop(ctx),
      ),
    ],
  );
}

// ── Sheet header (drag handle + title + optional close) ──────────────────────

class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showClose;
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showClose = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showClose)
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(AppIcons.close, color: AppTheme.inkSoft),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Segmented pill toggle (Cash/UPI/Card, Percent/Flat, etc.) ────────────────

class PillToggle extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const PillToggle({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.asMap().entries.map((e) {
        final selected = e.key == selectedIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: e.key == options.length - 1 ? 0 : 8,
            ),
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.accent : AppTheme.surface2,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.inkSoft,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Dashed/dotted border box (Add new plan / Invite staff pattern) ───────────

class DottedBorderBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const DottedBorderBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(radius: radius),
      child: Container(width: double.infinity, padding: padding, child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final double radius;
  const _DashedBorderPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.inkHint
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Attention row (icon chip + title + subtitle + chevron) ───────────────────

/// One actionable item in the dashboard's "Needs attention" card. Tinted icon
/// chip carries the severity; the row itself stays neutral so a stack of them
/// still reads as a list.
class AttentionTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color tintBg;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const AttentionTile({
    super.key,
    required this.icon,
    required this.tint,
    required this.tintBg,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  factory AttentionTile.danger({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) => AttentionTile(
    icon: icon,
    tint: AppTheme.statusDanger,
    tintBg: AppTheme.statusDangerBg,
    title: title,
    subtitle: subtitle,
    onTap: onTap,
  );

  factory AttentionTile.warn({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) => AttentionTile(
    icon: icon,
    tint: AppTheme.statusWarn,
    tintBg: AppTheme.statusWarnBg,
    title: title,
    subtitle: subtitle,
    onTap: onTap,
  );

  factory AttentionTile.info({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) => AttentionTile(
    icon: icon,
    tint: AppTheme.accent,
    tintBg: AppTheme.accentSoft,
    title: title,
    subtitle: subtitle,
    onTap: onTap,
  );

  factory AttentionTile.neutral({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) => AttentionTile(
    icon: icon,
    tint: AppTheme.statusNeutral,
    tintBg: AppTheme.statusNeutralBg,
    title: title,
    subtitle: subtitle,
    onTap: onTap,
  );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tintBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                AppIcons.chevronRight,
                size: 20,
                color: AppTheme.inkHint,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Compact stat tile (the "Today" strip) ───────────────────────────────────

/// Denser sibling of [StatTileLight] — label on top, number under it, sized
/// for four across on a phone.
class MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const MiniStat({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        decoration: AppTheme.cardDecoration(radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: AppTheme.numberStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card action button (the row of actions inside a member/dues card) ───────

/// Full-width-in-its-slot button used in card footers. `filled` is the one
/// primary action per card; the rest stay neutral so the primary reads first.
class CardAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final VoidCallback? onTap;

  const CardAction({
    super.key,
    required this.label,
    this.icon,
    this.filled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? AppTheme.accent : AppTheme.surface2;
    final fg = filled ? Colors.white : AppTheme.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty / error state ─────────────────────────────────────────────────────

/// The single empty-and-error state shape: tinted icon disc, one line of what
/// happened, one line of what to do, optional action.
class StateMessage extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color tintBg;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.tint = AppTheme.inkSoft,
    this.tintBg = AppTheme.surface2,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tintBg, shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: tint),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppTheme.inkSoft,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              PillButton(label: actionLabel!, onTap: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// The app-wide load-failure state. Never renders the raw exception — a gym
/// owner can't act on a stack trace, and it leaks internals into the UI.
class ErrorState extends StatelessWidget {
  final String what;
  final VoidCallback? onRetry;
  const ErrorState({super.key, required this.what, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return StateMessage(
      icon: AppIcons.cloudOff,
      tint: AppTheme.statusDanger,
      tintBg: AppTheme.statusDangerBg,
      title: 'Could not load $what',
      body: onRetry != null
          ? 'Check your connection, then try again.'
          : 'Check your connection, then pull down to retry.',
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
    );
  }
}

// ── Underline tab bar ────────────────────────────────────────────────────────

/// Flat text tabs with a teal underline on the active one, sitting on a
/// hairline rule (Money, Member detail). Scrolls horizontally when the labels
/// don't fit so a five-tab row never overflows on a narrow phone.
class UnderlineTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const UnderlineTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Trailing slack so the last label never sits flush against the clip
        // edge and lose its final character when scrolled fully right.
        padding: const EdgeInsets.only(right: 2),
        child: Row(
          children: tabs.asMap().entries.map((e) {
            final selected = e.key == selectedIndex;
            return GestureDetector(
              onTap: () => onChanged(e.key),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: EdgeInsets.only(
                  right: e.key == tabs.length - 1 ? 0 : 20,
                ),
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 11),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? AppTheme.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppTheme.ink : AppTheme.inkHint,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Label-over-value box ─────────────────────────────────────────────────────

/// The tappable "Joining date / Today, 27 Aug" box the member forms use —
/// a small label with the current value under it, opening a picker on tap.
class BoxField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const BoxField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 3),
            Text(
              value,
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
    );
  }
}

// ── Selectable chip ──────────────────────────────────────────────────────────

/// Teal-when-selected chip used for payment methods and member status, in
/// place of a dropdown.
class SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppTheme.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// Card body used by the member add/edit sheets — white, rounded, padded.
class SheetCard extends StatelessWidget {
  final Widget child;
  const SheetCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: AppTheme.cardDecoration(),
    child: child,
  );
}

/// Header for a full-height form sheet: close on the left, centred title.
class SheetTopBar extends StatelessWidget {
  final String title;
  const SheetTopBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(AppIcons.close, color: AppTheme.ink),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// Confirmation for a check-in, the action staff repeat most in a day.
///
/// It used to be a default grey SnackBar that read the same whether the member
/// was checked in, already inside, or rejected — and it faded before you could
/// register it at a busy front desk. This one is colour-coded, carries the
/// member's name, and stays long enough to read without blocking the next scan.
/// Takes the messenger rather than a BuildContext: the caller must capture it
/// *before* awaiting the check-in, because recording one refreshes the member
/// list and unmounts the row that started it — a context-based lookup then
/// finds nothing and the confirmation silently never appears.
void showCheckInResult(
  ScaffoldMessengerState messenger, {
  required bool success,
  required bool already,
  required String title,
  String? subtitle,
}) {
  // `already` is checked before `success`: the service reports an existing
  // check-in as success:false, but nothing went wrong — the member is simply
  // already inside. Red would read as a failure the staff member has to fix.
  final (fg, bg, icon) = already
      ? (AppTheme.statusWarn, AppTheme.statusWarnBg, AppIcons.history)
      : success
      ? (
          AppTheme.statusActive,
          AppTheme.statusActiveBg,
          AppIcons.checkCircleActive,
        )
      : (AppTheme.statusDanger, AppTheme.statusDangerBg, AppIcons.error);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        elevation: 0,
        duration: Duration(seconds: success && !already ? 3 : 5),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: fg.withValues(alpha: 0.25)),
        ),
        content: Row(
          children: [
            Icon(icon, color: fg, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fg.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
}
