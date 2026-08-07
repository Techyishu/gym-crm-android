import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../utils/platform_info.dart';

// iOS-only RevenueCat public SDK key (Apple App Store).
const _kRcApiKeyIos = 'appl_nIbDtTyPmDxXhpHcWKXfGoRRZyS';

/// The RC entitlement identifier configured in the RevenueCat dashboard.
const kRcEntitlement = 'gymcrm Pro';

class RevenueCatService {
  RevenueCatService._();

  static Future<void> initialize() async {
    if (!isIOS) return;
    await Purchases.setLogLevel(
      kReleaseMode ? LogLevel.error : LogLevel.verbose,
    );
    final config = PurchasesConfiguration(_kRcApiKeyIos);
    await Purchases.configure(config);
  }

  /// Call after Supabase sign-in so RC ties purchases to this user.
  static Future<void> loginUser(String userId) async {
    if (!isIOS) return;
    try {
      await Purchases.logIn(userId);
    } catch (e, s) {
      debugPrint('[RC] loginUser error: $e\n$s');
    }
  }

  /// Call on sign-out so RC resets to anonymous identity.
  static Future<void> logoutUser() async {
    if (!isIOS) return;
    try {
      await Purchases.logOut();
    } catch (e, s) {
      debugPrint('[RC] logoutUser error: $e\n$s');
    }
  }

  /// One-shot check — prefer the stream provider for reactive UI.
  static Future<bool> hasProAccess() async {
    if (!isIOS) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(kRcEntitlement);
    } catch (e) {
      debugPrint('[RC] hasProAccess error: $e');
      return false;
    }
  }
}
