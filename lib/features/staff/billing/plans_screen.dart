import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/responsive_content.dart';
import 'billing_screen.dart' show PlansBody;

/// New design's Plans page (Home → Plans). The same list, form and day-pass
/// option as Money's Plans tab in the old design.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Plans'), leading: const BackButton()),
      body: const ResponsiveContent(child: PlansBody()),
    );
  }
}
