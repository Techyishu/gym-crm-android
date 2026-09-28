import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI language, saved per phone (owner in Hindi, front desk in English is
/// fine). Display-only: nothing typed or stored is translated. Defaults to
/// English so nobody's app changes until they pick a language in Settings.
const _prefsKey = 'app_locale';

Future<bool> hasChosenAppLocale() async {
  try {
    return (await SharedPreferences.getInstance()).containsKey(_prefsKey);
  } catch (_) {
    return false;
  }
}

/// The language saved on this phone, read once in main() before runApp.
Future<Locale> loadSavedLocale() async {
  try {
    final code = (await SharedPreferences.getInstance()).getString(_prefsKey);
    return Locale(code == 'hi' ? 'hi' : 'en');
  } catch (_) {
    return const Locale('en');
  }
}

final appLocaleProvider = StateProvider<Locale>((ref) => const Locale('en'));

/// Switches the app language and remembers it on this phone.
Future<void> setAppLocale(WidgetRef ref, Locale locale) async {
  ref.read(appLocaleProvider.notifier).state = locale;
  try {
    await (await SharedPreferences.getInstance()).setString(
      _prefsKey,
      locale.languageCode,
    );
  } catch (_) {
    // Not saved: the choice still applies until the app restarts.
  }
}
