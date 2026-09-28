import 'package:flutter/widgets.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// `context.l10n.someText` — the current UI language's copy (see app_locale.dart).
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
