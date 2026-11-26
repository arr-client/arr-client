import 'dart:async';
import 'dart:math';

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/radarr_localizations.dart';

/// The wide picture above a movie; nothing where there is none to load.
class MovieBackdrop extends StatelessWidget {
  /// Creates a [MovieBackdrop].
  const MovieBackdrop({required this.movie, required this.artwork, super.key});

  /// Whose picture.
  final Movie movie;

  /// Loads it.
  final ArtworkLoader artwork;

  static const _maxHeight = 240.0;

  @override
  Widget build(BuildContext context) {
    final source = _image(movie, MediaImageType.fanart, artwork);
    if (source == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: min(constraints.maxWidth * 9 / 16, _maxHeight),
        child: _Picture(
          source: source,
          width: constraints.maxWidth,
          placeholder: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

/// A movie's poster, title and state. Monitoring is shown by its switch.
class MovieHeader extends StatelessWidget {
  /// Creates a [MovieHeader].
  const MovieHeader({
    required this.movie,
    required this.instanceName,
    required this.artwork,
    super.key,
  });

  /// The movie.
  final Movie movie;

  /// The instance that holds it, which tells two copies apart.
  final String instanceName;

  /// Loads the poster.
  final ArtworkLoader artwork;

  static const _posterWidth = 112.0;

  /// The least width, at the usual text size, for the poster to sit beside the
  /// text.
  static const _besideFrom = 300.0;

  @override
  Widget build(BuildContext context) {
    final strings = RadarrLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Its own node, or the lines below would be read as part of the heading.
        Semantics(
          container: true,
          header: true,
          child: Text(movie.title, style: theme.textTheme.headlineSmall),
        ),
        if (movie.year case final year?) Text('$year'),
        const SizedBox(height: 8),
        ItemStateLine(movie.state),
        const SizedBox(height: 4),
        Text(
          strings.movieOnInstance(instanceName),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );

    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.movie_outlined, color: colors.onSurfaceVariant),
      ),
    );
    final source =
        _image(movie, MediaImageType.poster, artwork) ??
        _image(movie, MediaImageType.cover, artwork);
    final poster = SizedBox(
      width: _posterWidth,
      height: _posterWidth * 3 / 2,
      child: source == null
          ? placeholder
          : _Picture(
              source: source,
              width: _posterWidth,
              placeholder: placeholder,
            ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        return constraints.maxWidth / scale >= _besideFrom
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  poster,
                  const SizedBox(width: 16),
                  Expanded(child: details),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [poster, const SizedBox(height: 16), details],
              );
      },
    );
  }
}

/// A picture, decoded at about the size it is shown, over [placeholder] until
/// it has loaded and where it cannot.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.source,
    required this.width,
    required this.placeholder,
  });

  final ImageProvider<Object> source;
  final double width;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final image = ResizeImage(
      source,
      width: (width * MediaQuery.devicePixelRatioOf(context)).ceil(),
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
        // So that it is tried again when next shown.
        unawaited(image.evict());
        return placeholder;
      },
    );
  }
}

ImageProvider<Object>? _image(
  Movie movie,
  MediaImageType type,
  ArtworkLoader artwork,
) {
  final picture = movie.images.where((image) => image.type == type).firstOrNull;
  return picture == null ? null : artwork.image(picture);
}
