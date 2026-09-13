import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/services/app_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase is only initialised on Android, so every AppEvents call has to skip
/// it on iOS — touching `FirebaseAnalytics.instance` there throws. Meta, in
/// contrast, must still run on iOS or the ad account has no conversion data and
/// Aggregated Event Measurement can't be configured.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const metaChannel = MethodChannel('flutter.oddbit.id/facebook_app_events');
  final metaCalls = <String>[];

  setUp(() {
    metaCalls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(metaChannel, (
      call,
    ) async {
      metaCalls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(metaChannel, null);
  });

  test('iOS with ads consent sends Meta events and skips Firebase', () async {
    SharedPreferences.setMockInitialValues({'consent_ads': true});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await AppEvents.checkinCompleted();
    await AppEvents.signUpCompleted();
    await AppEvents.purchase(amount: 299);

    // Reaching here at all means Firebase was never touched — it isn't
    // initialised on iOS, so any call would have thrown.
    expect(metaCalls, isNotEmpty);
  });

  test('iOS without ads consent sends nothing', () async {
    SharedPreferences.setMockInitialValues({'consent_ads': false});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await AppEvents.checkinCompleted();
    await AppEvents.signUpCompleted();
    await AppEvents.purchase(amount: 299);

    expect(metaCalls, isEmpty);
  });
}
