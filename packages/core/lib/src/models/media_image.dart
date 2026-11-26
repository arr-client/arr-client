import 'media_image_type.dart';

/// Artwork, on the instance or on a public host.
final class MediaImage {
  /// Creates a [MediaImage].
  const MediaImage({required this.type, this.instancePath, this.remoteUrl});

  /// What it shows.
  final MediaImageType type;

  /// Relative to the instance's address, possibly with a query.
  final String? instancePath;

  /// Loaded without credentials.
  final Uri? remoteUrl;
}
