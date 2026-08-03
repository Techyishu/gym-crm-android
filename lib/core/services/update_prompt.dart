import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Google Play in-app update prompt. Play itself knows what version is live, so
/// there is no version endpoint to maintain and nothing to bump on release.
///
/// Only fires for full store releases — Shorebird patches ship silently and
/// don't change the Play version code, so Play sees no update available.
class UpdatePrompt {
  /// Flexible update: user keeps using the app while the APK downloads in the
  /// background, then Play installs it. Immediate (blocking) updates are for
  /// shipping a fix to a broken build — not for routine releases.
  static Future<void> check() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      await InAppUpdate.startFlexibleUpdate();
      await InAppUpdate.completeFlexibleUpdate();
    } catch (_) {
      // Sideloaded build, no Play account, already-in-progress flow, user
      // dismissed. None of it is actionable and none of it should surface.
    }
  }
}
