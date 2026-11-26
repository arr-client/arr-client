import 'availability.dart';
import 'discovery_media_type.dart';
import 'media_image.dart';
import 'request_status.dart';

/// A title known to a request service.
final class DiscoveryTitle {
  /// Creates a [DiscoveryTitle].
  const DiscoveryTitle({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    required this.availability,
    required this.availability4k,
    this.mediaId,
    this.tvdbId,
    this.year,
    this.poster,
    this.requestStatus,
    this.requestStatus4k,
  });

  /// The TMDB id.
  final int tmdbId;

  /// The server's own media record, present only for titles it knows.
  final int? mediaId;

  /// Movie or series.
  final DiscoveryMediaType mediaType;

  /// The title.
  final String title;

  /// With [tmdbId], matches the title against library search results.
  final int? tvdbId;

  /// Year of first release.
  final int? year;

  /// Poster artwork.
  final MediaImage? poster;

  /// Availability of the standard variant.
  final Availability availability;

  /// Availability of the 4K variant.
  final Availability availability4k;

  /// Status of a request for the standard variant.
  final RequestStatus? requestStatus;

  /// Status of a request for the 4K variant.
  final RequestStatus? requestStatus4k;
}
