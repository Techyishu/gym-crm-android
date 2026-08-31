import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Centers [child] with a max width once the viewport is wider than a phone
/// (Flutter web on desktop) — screens built for phone-width layouts render
/// unchanged below the breakpoint, just no longer stretch edge-to-edge on
/// wide browser windows.
class ResponsiveContent extends StatelessWidget {
  final Widget child;
  static const double breakpoint = 700;
  static const double maxWidth = 720;

  /// Above this width there's room for a persistent sidebar instead of a
  /// bottom nav bar, and multi-column layouts instead of single-column.
  static const double sidebarBreakpoint = 900;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= sidebarBreakpoint;

  const ResponsiveContent({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < breakpoint) return child;
    return ColoredBox(
      color: AppTheme.background,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width >= sidebarBreakpoint ? 1100 : maxWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}
