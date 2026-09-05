import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/services/member_photo_service.dart';

/// Renders a member photo that requires an auth header to fetch. Native
/// platforms pass the header straight to [CachedNetworkImage]. Web fetches
/// the bytes manually via [MemberPhotoService.fetchBytes] instead, since
/// Flutter Web's image pipeline drops custom headers — see
/// [MemberPhotoService.photoUrl] for why.
class AuthedMemberImage extends StatelessWidget {
  final String? stored;
  final BoxFit fit;
  final Widget Function(BuildContext context, ImageProvider image)?
      imageBuilder;
  final Widget Function(BuildContext context)? placeholder;
  final Widget Function(BuildContext context)? errorWidget;

  const AuthedMemberImage({
    super.key,
    required this.stored,
    this.fit = BoxFit.cover,
    this.imageBuilder,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final path = MemberPhotoService.pathFrom(stored);
    if (path == null) {
      return errorWidget?.call(context) ?? const SizedBox.shrink();
    }

    if (!kIsWeb) {
      return CachedNetworkImage(
        imageUrl: MemberPhotoService.photoUrl(stored)!,
        httpHeaders: MemberPhotoService.authHeaders(),
        cacheKey: path,
        fit: imageBuilder == null ? fit : null,
        imageBuilder: imageBuilder,
        placeholder:
            placeholder == null ? null : (ctx, _) => placeholder!(ctx),
        errorWidget:
            errorWidget == null ? null : (ctx, _, __) => errorWidget!(ctx),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: MemberPhotoService.fetchBytes(stored),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return placeholder?.call(context) ?? const SizedBox.shrink();
        }
        final bytes = snap.data;
        if (bytes == null) {
          return errorWidget?.call(context) ?? const SizedBox.shrink();
        }
        final image = MemoryImage(bytes);
        return imageBuilder?.call(context, image) ??
            Image(image: image, fit: fit);
      },
    );
  }
}
