import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../services/revenue_cat_service.dart';
import '../utils/platform_info.dart';

/// Live stream of CustomerInfo from RevenueCat (iOS only).
/// Emits null on Android — callers must guard with Platform.isIOS.
final customerInfoProvider = StreamProvider<CustomerInfo?>((ref) {
  if (!isIOS) return Stream.value(null);

  final controller = StreamController<CustomerInfo?>.broadcast();

  // Fetch current value immediately so UI doesn't wait for the first update.
  Purchases.getCustomerInfo().then(
    (info) {
      if (!controller.isClosed) controller.add(info);
    },
    onError: (_) {
      if (!controller.isClosed) controller.add(null);
    },
  );

  void listener(CustomerInfo info) {
    if (!controller.isClosed) controller.add(info);
  }

  Purchases.addCustomerInfoUpdateListener(listener);

  ref.onDispose(() {
    Purchases.removeCustomerInfoUpdateListener(listener);
    controller.close();
  });

  return controller.stream;
});

/// true when the iOS user holds an active "gymcrm Pro" entitlement.
/// Always false on Android (Android billing goes through Supabase / Dodo).
final iosProAccessProvider = Provider<bool>((ref) {
  if (!isIOS) return false;
  final async = ref.watch(customerInfoProvider);
  return async.valueOrNull?.entitlements.active.containsKey(kRcEntitlement) ??
      false;
});
