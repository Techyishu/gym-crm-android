import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Google Play in-app update prompt. Play itself knows what version is live, so
/// there is no version endpoint to maintain and nothing to bump on release.
///
/// Only fires for full store releases — Shorebird patches ship silently and
/// don't change the Play version code, so Play sees no update available.
class UpdatePrompt {
  /// Immediate update: Play shows its own full-screen blocking UI — user can't
  /// use the app until they update (or the OS back-cancels it, which just
  /// re-blocks on next check). No custom screen needed, Play owns that UI.
  static Future<void> check() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      await InAppUpdate.performImmediateUpdate();
    } catch (_) {
      // Sideloaded build, no Play account, already-in-progress flow, user
      // dismissed. None of it is actionable and none of it should surface.
    }
  }
}
