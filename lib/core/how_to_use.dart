import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';

/// "How to use GymCRM" tutorial playlist (unlisted YouTube videos).
final _howToUseUri = Uri.parse(
  'https://www.youtube.com/playlist?list=PLdEekZJJRdQg',
);

Future<void> openHowToUse(BuildContext context) async {
  final opened = await launchUrl(
    _howToUseUri,
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.howToUseOpenFailed)));
  }
}
