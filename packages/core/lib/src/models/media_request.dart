import 'availability.dart';
import 'discovery_ref.dart';
import 'request_status.dart';
import 'service_user.dart';

/// A request for a title.
final class MediaRequest {
  /// Creates a [MediaRequest].
  const MediaRequest({
    required this.id,
    required this.titleRef,
    required this.requestedBy,
    required this.status,
    required this.availability,
    required this.is4k,
    this.seasons = const [],
  });

  /// The server's id of the request.
  final int id;

  /// The title requested.
  final DiscoveryRef titleRef;

  /// Who asked.
  final ServiceUser requestedBy;

  /// Where the request is.
  final RequestStatus status;

  /// Availability of the requested variant.
  final Availability availability;

  /// Requested seasons; empty for a movie.
  final List<int> seasons;

  /// Whether the 4K variant was requested.
  final bool is4k;
}
