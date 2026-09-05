import 'package:flutter/material.dart';

import '../../core/services/member_photo_service.dart';
import 'authed_member_image.dart';

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
    if (MemberPhotoService.pathFrom(stored) == null) return fallback;
    return ClipOval(
      child: AuthedMemberImage(
        stored: stored,
        fit: fit,
        errorWidget: (_) => fallback,
      ),
    );
  }
}
