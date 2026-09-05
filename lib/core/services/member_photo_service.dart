import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Member photos are served by a Cloudflare Worker backed by R2 (not
/// Supabase Storage — moved off it to avoid Supabase egress billing). The
/// Worker checks the caller's gym_id against the path's gymId prefix in
/// place of the RLS check Supabase Storage used to do, so every request
/// must carry the user's current Supabase access token.
class MemberPhotoService {
  MemberPhotoService._();

  static const _workerBase =
      'https://gym-crm-photo-proxy.ishansingh687.workers.dev';

  static const _byteCacheTtl = Duration(minutes: 55);
  static final Map<String, _CachedBytes> _byteCache = {};

  /// Builds the Worker URL for a stored avatar value. Accepts plain paths
  /// ('gymId/file.png') and legacy Supabase public/signed URLs.
  ///
  /// Native platforms pass [authHeaders] straight to [CachedNetworkImage],
  /// which is enough — this URL never carries the token. On web, use
  /// [fetchBytes] instead: Flutter Web's image pipeline renders via a
  /// browser <img> element that silently drops custom headers, so a plain
  /// URL there has no way to authenticate.
  static String? photoUrl(String? stored) {
    final path = pathFrom(stored);
    if (path == null) return null;
    return '$_workerBase/$path';
  }

  /// Auth header required by the Worker on every request.
  static Map<String, String> authHeaders() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }

  /// Fetches photo bytes with the auth token in a header (never a URL) —
  /// the web-safe equivalent of [photoUrl] + [authHeaders]. Cached in
  /// memory for 55 minutes per path.
  static Future<Uint8List?> fetchBytes(String? stored) async {
    final path = pathFrom(stored);
    if (path == null) return null;

    final hit = _byteCache[path];
    if (hit != null && DateTime.now().difference(hit.at) < _byteCacheTtl) {
      return hit.bytes;
    }

    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$_workerBase/$path'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return null;
      _byteCache[path] = _CachedBytes(res.bodyBytes, DateTime.now());
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
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
    await CachedNetworkImage.evictFromCache(
      '$_workerBase/$path',
      cacheKey: path,
    );
    _byteCache.remove(path);
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

class _CachedBytes {
  final Uint8List bytes;
  final DateTime at;
  _CachedBytes(this.bytes, this.at);
}
