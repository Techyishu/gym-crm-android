import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Member photos are served by a Cloudflare Worker backed by R2 (not
/// Supabase Storage — moved off it to avoid Supabase egress billing). The
/// Worker checks the caller's gym_id against the path's gymId prefix in
/// place of the RLS check Supabase Storage used to do, so every request
/// must carry the user's current Supabase access token.
class MemberPhotoService {
  MemberPhotoService._();

  static const _workerBase = 'https://gym-crm-photo-proxy.ishansingh687.workers.dev';

  /// Builds the Worker URL for a stored avatar value. Accepts plain paths
  /// ('gymId/file.png') and legacy Supabase public/signed URLs.
  ///
  /// On web, the token rides as a `?token=` query param instead of (only) an
  /// Authorization header — CachedNetworkImage renders via a native <img>
  /// tag on web, which can't carry custom headers at all, so a header-only
  /// auth request there always 401s. The Worker already accepts either.
  static String? photoUrl(String? stored) {
    final path = pathFrom(stored);
    if (path == null) return null;
    if (!kIsWeb) return '$_workerBase/$path';

    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return '$_workerBase/$path';
    return '$_workerBase/$path?token=${Uri.encodeQueryComponent(token)}';
  }

  /// Auth header required by the Worker on every request.
  static Map<String, String> authHeaders() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }

  /// Uploads photo bytes to the given storage path via the Worker.
  static Future<void> upload({
    required String path,
    required List<int> bytes,
    required String contentType,
  }) async {
    final res = await http.put(
      Uri.parse('$_workerBase/$path'),
      headers: {...authHeaders(), 'Content-Type': contentType},
      body: bytes,
    );
    if (res.statusCode != 204) {
      throw Exception('Photo upload failed (${res.statusCode})');
    }
    // path is a stable per-member key for re-uploads (member_detail_screen),
    // so evict it or every CachedNetworkImage keyed on this path keeps
    // serving the old bytes until the disk cache naturally expires.
    await CachedNetworkImage.evictFromCache('$_workerBase/$path', cacheKey: path);
  }

  static String? pathFrom(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (!stored.startsWith('http')) return stored;
    const marker = '/member-photos/';
    final i = stored.indexOf(marker);
    if (i == -1) return null;
    return Uri.decodeFull(stored.substring(i + marker.length).split('?').first);
  }
}
