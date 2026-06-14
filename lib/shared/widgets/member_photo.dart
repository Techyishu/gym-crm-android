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
    if (stored == null || stored!.isEmpty) return fallback;
    return FutureBuilder<String?>(
      future: MemberPhotoService.signedUrl(stored),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) return fallback;
        return ClipOval(
          child: Image.network(
            url,
            fit: fit,
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
      },
    );
  }
}
