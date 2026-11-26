import 'dart:async';

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

/// The poster or cover of an item, or a placeholder where there is none to
/// load. It fills the space it is given and is decoded at about that size.
class LibraryPoster extends StatelessWidget {
  const LibraryPoster({
    required this.item,
    required this.artwork,
    required this.width,
    super.key,
  });

  final LibraryItem item;
  final ArtworkLoader artwork;

  /// About how wide it is shown, in logical pixels.
  final double width;

  /// Decoded widths come in steps, so that a small change of layout does not
  /// decode everything again.
  static const _step = 64;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(switch (item.ref.kind) {
          MediaKind.series || MediaKind.episode => Icons.tv_outlined,
          MediaKind.artist ||
          MediaKind.album ||
          MediaKind.track => Icons.album_outlined,
          MediaKind.author || MediaKind.book => Icons.book_outlined,
          MediaKind.movie => Icons.movie_outlined,
        }, color: colors.onSurfaceVariant),
      ),
    );
    final picture =
        item.images
            .where((image) => image.type == MediaImageType.poster)
            .firstOrNull ??
        item.images
            .where((image) => image.type == MediaImageType.cover)
            .firstOrNull;
    final source = picture == null ? null : artwork.image(picture);
    if (source == null) return placeholder;
    final pixels = width * MediaQuery.devicePixelRatioOf(context);
    final image = ResizeImage(
      source,
      width: (pixels / _step).ceil() * _step,
      policy: ResizeImagePolicy.fit,
    );
    return Image(
      image: image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame == null && !wasSynchronouslyLoaded ? placeholder : child,
      errorBuilder: (context, error, stackTrace) {
        // The resized picture has a key of its own, under which a failure
        // would otherwise stay: forgotten, it is tried again when next shown.
        unawaited(image.evict());
        return placeholder;
      },
    );
  }
}
