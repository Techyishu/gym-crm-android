import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'member_photo.dart';

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
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
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

  const StatusPill({super.key, required this.label, required this.color, required this.bg});

  factory StatusPill.active({String label = 'Active'}) =>
      StatusPill(label: label, color: AppTheme.statusActive, bg: AppTheme.statusActiveBg);
  factory StatusPill.warn({String label = 'Lapsing'}) =>
      StatusPill(label: label, color: AppTheme.statusWarn, bg: AppTheme.statusWarnBg);
  factory StatusPill.danger({String label = 'Expired'}) =>
      StatusPill(label: label, color: AppTheme.statusDanger, bg: AppTheme.statusDangerBg);
  factory StatusPill.neutral({String label = 'On hold'}) =>
      StatusPill(label: label, color: AppTheme.statusNeutral, bg: AppTheme.statusNeutralBg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
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
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
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

  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.ink)),
        const Spacer(),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accent),
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

  const StatTileLight({super.key, required this.label, required this.value, this.onTap});

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
              child: Text(label, maxLines: 1,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.inkSoft)),
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

  const PillButton({super.key, required this.label, this.onTap, this.filled = true, this.color});

  @override
  Widget build(BuildContext context) {
    final bg = filled ? (color ?? AppTheme.accent) : AppTheme.surface2;
    final fg = filled ? Colors.white : AppTheme.ink;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
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

  const RoundIconButton({super.key, required this.icon, this.onTap, this.bg, this.fg, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg ?? AppTheme.surface2, shape: BoxShape.circle),
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
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String cancelLabel = 'Cancel',
  required String confirmLabel,
  IconData icon = Icons.error_outline,
  bool danger = true,
}) {
  final tint = danger ? AppTheme.statusDanger : AppTheme.accent;
  final tintBg = danger ? AppTheme.statusDangerBg : AppTheme.accentSoft;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: tintBg, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, size: 26, color: tint),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: AppTheme.inkSoft, height: 1.4)),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: Text(cancelLabel,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: Text(confirmLabel,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

// ── Sheet header (drag handle + title + optional close) ──────────────────────

class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showClose;
  const SheetHeader({super.key, required this.title, this.subtitle, this.showClose = true});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(
        child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
        ),
      ),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.ink)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
            ],
          ]),
        ),
        if (showClose)
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: AppTheme.inkSoft),
          ),
      ]),
    ]);
  }
}

// ── Segmented pill toggle (Cash/UPI/Card, Percent/Flat, etc.) ────────────────

class PillToggle extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const PillToggle({super.key, required this.options, required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.asMap().entries.map((e) {
        final selected = e.key == selectedIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key == options.length - 1 ? 0 : 8),
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.accent : AppTheme.surface2,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Text(e.value,
                  style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.inkSoft,
                  )),
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
      child: Container(
        width: double.infinity,
        padding: padding,
        child: child,
      ),
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
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
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
