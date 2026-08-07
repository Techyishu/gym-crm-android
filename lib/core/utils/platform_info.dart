import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io;

/// Web-safe replacement for `dart:io`'s `Platform.isIOS`.
///
/// `dart:io`'s `Platform` throws `UnsupportedError` on web, so every call
/// site must check `kIsWeb` first. Centralised here instead of repeating
/// the guard at each of the ~20 call sites.
bool get isIOS => !kIsWeb && io.Platform.isIOS;
