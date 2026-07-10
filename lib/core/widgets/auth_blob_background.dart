import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Decorative teal blobs bleeding off the top-right and bottom-left
/// corners, used behind the login/signup forms. Pure background dressing —
/// no interaction, no state.
class AuthBlobBackground extends StatelessWidget {
  final Widget child;
  const AuthBlobBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -70,
          right: -60,
          child: _blob(220, AppTheme.accent.withValues(alpha: 0.16)),
        ),
        Positioned(
          bottom: -90,
          left: -80,
          child: _blob(260, AppTheme.accent.withValues(alpha: 0.10)),
        ),
        child,
      ],
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
