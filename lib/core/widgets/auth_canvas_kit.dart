import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared auth pieces, styled to match the Orbit welcome screen.

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
          minimumSize: const Size(44, 44),
          alignment: Alignment.centerLeft,
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
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.12,
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

class OrbitBrandPanel extends StatelessWidget {
  final String label;
  final String headline;

  const OrbitBrandPanel({
    super.key,
    this.label = 'WELCOME TO GYMCRM',
    this.headline = 'Move your gym forward.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 164,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            width: 190,
            height: 190,
            right: -44,
            top: -70,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: .16),
                ),
              ),
            ),
          ),
          Positioned(
            width: 132,
            height: 132,
            right: -8,
            top: -18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: .12),
                ),
              ),
            ),
          ),
          Positioned(
            right: -18,
            bottom: -24,
            width: 210,
            height: 180,
            child: Image.asset(
              'assets/illustrations/gymcrm_welcome_hero.png',
              fit: BoxFit.contain,
              alignment: Alignment.bottomRight,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          Positioned(
            left: 18,
            top: 14,
            child: Image.asset(
              'assets/branding/gymcrm-logo-horizontal-theme.png',
              width: 122,
              height: 40,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, _, _) => const Text(
                'GymCRM',
                style: TextStyle(
                  color: AppTheme.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 170,
            bottom: 17,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 20,
                    height: 1.04,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OrbitFormCard extends StatelessWidget {
  final List<Widget> children;
  const OrbitFormCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D1D1B16),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 6, 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accent.withValues(alpha: .11)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .75,
                  color: AppTheme.accent,
                ),
              ),
              if (optional) ...[
                const SizedBox(width: 6),
                const Text(
                  'OPTIONAL',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkHint,
                  ),
                ),
              ],
            ],
          ),
          child,
        ],
      ),
    );
  }
}

InputDecoration canvasFieldDecoration({String? hint}) => InputDecoration(
  hintText: hint,
  filled: false,
  contentPadding: const EdgeInsets.fromLTRB(0, 7, 10, 10),
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
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
      height: 56,
      child: Stack(
        children: [
          ElevatedButton(
            onPressed: loading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.accentFg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              textStyle: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(child: Text(label)),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.arrow_forward_rounded, size: 21),
                ),
              ],
            ),
          ),
          if (loading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.accentDark,
                  borderRadius: BorderRadius.circular(20),
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
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.ink,
          side: const BorderSide(color: AppTheme.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
