import 'discovery_media_type.dart';

/// Refers to a title in a request service.
final class DiscoveryRef {
  const DiscoveryRef({required this.mediaType, required this.tmdbId});

  final DiscoveryMediaType mediaType;
  final int tmdbId;

  @override
  bool operator ==(Object other) =>
      other is DiscoveryRef &&
      other.mediaType == mediaType &&
      other.tmdbId == tmdbId;

  @override
  int get hashCode => Object.hash(mediaType, tmdbId);
}
