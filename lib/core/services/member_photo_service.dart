import 'package:supabase_flutter/supabase_flutter.dart';

/// The member-photos bucket is private: stored values are storage paths
/// (legacy rows may still hold full public URLs) and must be resolved to a
/// short-lived signed URL before rendering.
class MemberPhotoService {
  MemberPhotoService._();

  static const _bucket = 'member-photos';
  static const _signedUrlExpiry = 3600; // seconds
  static const _cacheTtl = Duration(minutes: 55);

  static final Map<String, (DateTime, Future<String?>)> _cache = {};

  /// Resolves a stored avatar value (path or legacy public URL) to a signed
  /// URL. Results are cached below the signed-URL expiry and shared between
  /// concurrent callers, so lists don't re-sign per row.
  static Future<String?> signedUrl(String? stored) {
    final path = pathFrom(stored);
    if (path == null) return Future.value(null);

    final hit = _cache[path];
    if (hit != null && DateTime.now().difference(hit.$1) < _cacheTtl) {
      return hit.$2;
    }

    final future = Supabase.instance.client.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlExpiry)
        .then<String?>((url) => url)
        .catchError((_) {
      _cache.remove(path);
      return null;
    });
    _cache[path] = (DateTime.now(), future);
    return future;
  }

  /// Extracts the storage path from a stored value. Accepts plain paths
  /// ('gymId/file.png') and legacy public/signed URLs.
  static String? pathFrom(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (!stored.startsWith('http')) return stored;
    const marker = '/member-photos/';
    final i = stored.indexOf(marker);
    if (i == -1) return null;
    return Uri.decodeFull(stored.substring(i + marker.length).split('?').first);
  }
}
