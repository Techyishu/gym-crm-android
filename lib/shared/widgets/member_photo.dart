import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/services/member_photo_service.dart';

/// Renders a member photo from its stored value (storage path or legacy
/// public URL) by resolving a signed URL first — the member-photos bucket is
/// private, so Image.network on the stored value alone would fail.
/// [fallback] is shown while resolving, on error, or when there is no photo.
class MemberPhoto extends StatelessWidget {
  final String? stored;
  final BoxFit fit;
  final Widget fallback;

  const MemberPhoto({
    super.key,
    required this.stored,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final url = MemberPhotoService.photoUrl(stored);
    if (url == null) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: MemberPhotoService.authHeaders(),
        cacheKey: MemberPhotoService.pathFrom(stored),
        fit: fit,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}
