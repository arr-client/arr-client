import 'availability.dart';
import 'discovery_ref.dart';
import 'request_status.dart';
import 'service_user.dart';

/// A request for a title.
final class MediaRequest {
  const MediaRequest({
    required this.id,
    required this.titleRef,
    required this.requestedBy,
    required this.status,
    required this.availability,
    required this.is4k,
    this.seasons = const [],
  });

  final int id;

  final DiscoveryRef titleRef;

  final ServiceUser requestedBy;

  final RequestStatus status;

  final Availability availability;

  final List<int> seasons;

  final bool is4k;
}
