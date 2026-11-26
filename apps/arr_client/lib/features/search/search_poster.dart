import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import 'search_hit.dart';

const searchPosterSize = Size(80, 120);

/// The poster of a result, or a placeholder where there is none to load.
class SearchPoster extends ConsumerWidget {
  const SearchPoster({required this.hit, super.key});

  final SearchHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The loader reads the preference when it makes the image: made again when
    // it changes.
    ref.watch(
      preferencesProvider.select((value) => value.loadThirdPartyArtwork),
    );
    final id = hit.artworkInstanceId;
    final artwork = id == null
        ? null
        : ref.watch(scopeProvider)?.instance(id)?.context.artwork;
    final picture =
        _first(MediaImageType.poster) ?? _first(MediaImageType.cover);
    final source = picture == null ? null : artwork?.image(picture);

    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(switch (hit.kind) {
          MediaKind.series || MediaKind.episode => Icons.tv_outlined,
          MediaKind.artist ||
          MediaKind.album ||
          MediaKind.track => Icons.album_outlined,
          MediaKind.author || MediaKind.book => Icons.book_outlined,
          MediaKind.movie => Icons.movie_outlined,
        }, color: colors.onSurfaceVariant),
      ),
    );
    return SizedBox.fromSize(
      size: searchPosterSize,
      child: source == null
          ? placeholder
          : _picture(context, source, placeholder),
    );
  }

  MediaImage? _first(MediaImageType type) =>
      hit.images.where((image) => image.type == type).firstOrNull;

  Widget _picture(
    BuildContext context,
    ImageProvider<Object> source,
    Widget placeholder,
  ) {
    final image = ResizeImage(
      source,
      width: (searchPosterSize.width * MediaQuery.devicePixelRatioOf(context))
          .ceil(),
      policy: ResizeImagePolicy.fit,
    );
    return Image(
      image: image,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame == null && !wasSynchronouslyLoaded ? placeholder : child,
      errorBuilder: (context, error, stackTrace) {
        // The resized picture has a key of its own, under which a failure
        // would otherwise stay.
        unawaited(image.evict());
        return placeholder;
      },
    );
  }
}
