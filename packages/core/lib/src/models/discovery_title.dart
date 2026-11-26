import 'availability.dart';
import 'discovery_media_type.dart';
import 'media_image.dart';
import 'request_status.dart';

/// A title known to a request service.
final class DiscoveryTitle {
  const DiscoveryTitle({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    required this.availability,
    required this.availability4k,
    this.mediaId,
    this.poster,
    this.requestStatus,
    this.requestStatus4k,
  });

  final int tmdbId;

  /// The server's own media record, present only for titles it knows.
  final int? mediaId;

  final DiscoveryMediaType mediaType;

  final String title;

  final MediaImage? poster;

  final Availability availability;

  final Availability availability4k;

  final RequestStatus? requestStatus;

  final RequestStatus? requestStatus4k;
}
