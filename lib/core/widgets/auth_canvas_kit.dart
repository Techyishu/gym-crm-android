import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared pieces for the `Auth & Gym Setup.dc.html` canvas restyle — a
/// boxier, less-rounded look (12px radius, bordered fields with a label
/// above) than the older [AuthPillField] kit, used consistently across the
/// welcome/login/signup/forgot-password/member screens redesigned
/// 2026-08-28. See [[canvas-auth-gym-setup]].

/// "← Back" text button, top-left of a screen.
class CanvasBack extends StatelessWidget {
  final VoidCallback onTap;
  const CanvasBack({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          '← Back',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// Small uppercase teal label identifying which path a screen belongs to
/// ("GYM OWNER" / "GYM MEMBER").
class CanvasKicker extends StatelessWidget {
  final String text;
  const CanvasKicker(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: AppTheme.accent,
      ),
    );
  }
}

/// Title + optional subtitle block used at the top of every canvas screen.
class CanvasHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  const CanvasHeading({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.2,
            color: AppTheme.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 14.5,
              color: AppTheme.inkSoft,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Label above a bordered 12px-radius field — the canvas's field pattern,
/// boxier than [AuthPillField]'s full pill shape.
class CanvasField extends StatelessWidget {
  final String label;
  final bool optional;
  final Widget child;
  const CanvasField({
    super.key,
    required this.label,
    this.optional = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            if (optional) ...[
              const SizedBox(width: 6),
              const Text(
                '— optional',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkHint,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

InputDecoration canvasFieldDecoration({String? hint}) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: AppTheme.surface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppTheme.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppTheme.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppTheme.statusDanger),
  ),
);

/// Full-width teal button with an inline "Verifying…"-style loading overlay,
/// matching every primary CTA in the canvas.
class CanvasButton extends StatelessWidget {
  final String label;
  final String? loadingLabel;
  final bool loading;
  final VoidCallback? onPressed;
  const CanvasButton({
    super.key,
    required this.label,
    this.loadingLabel,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          ElevatedButton(
            onPressed: loading ? null : onPressed,
            child: Text(label),
          ),
          if (loading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.accentDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      loadingLabel ?? '$label…',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Secondary (outlined) button — "Back to log in" style.
class CanvasSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const CanvasSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.ink,
          side: const BorderSide(color: AppTheme.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

/// N-segment progress bar (4 segments in every wizard-style canvas flow).
class CanvasProgress extends StatelessWidget {
  final int total;
  final int filled;
  const CanvasProgress({super.key, required this.total, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
            height: 4,
            decoration: BoxDecoration(
              color: i < filled ? AppTheme.accent : AppTheme.surface2,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        );
      }),
    );
  }
}

/// Tinted inline banner for form-level errors — colours pulled from the
/// canvas's BANNERS map (danger/warn tones already in [AppTheme]).
class CanvasBanner extends StatelessWidget {
  final String message;
  final bool danger;
  const CanvasBanner({super.key, required this.message, this.danger = true});

  @override
  Widget build(BuildContext context) {
    final bg = danger ? AppTheme.statusDangerBg : AppTheme.statusWarnBg;
    final fg = danger ? AppTheme.statusDanger : AppTheme.statusWarn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: fg.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.5,
        ),
      ),
    );
  }
}

/// "Show/Hide" text toggle used inline in canvas password fields, in place
/// of an eye icon.
class CanvasShowToggle extends StatelessWidget {
  final bool obscured;
  final VoidCallback onTap;
  const CanvasShowToggle({
    super.key,
    required this.obscured,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 0),
      ),
      child: Text(
        obscured ? 'Show' : 'Hide',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.accent,
        ),
      ),
    );
  }
}
