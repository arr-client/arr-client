/// Whether a variant of a title is offered for request.
library;

import 'package:core/core.dart';

/// Why a variant is not offered for request.
enum RequestBlock {
  /// The user may not request it.
  notPermitted,

  /// The server blocks it.
  blocklisted,

  /// It is there already.
  available,

  /// It has been asked for already.
  requested,
}

/// Whether [permissions] allow requesting [type] in the chosen variant.
bool mayRequest(
  Set<ServicePermission> permissions,
  DiscoveryMediaType type, {
  required bool is4k,
}) => permissions.contains(switch ((type, is4k)) {
  (DiscoveryMediaType.movie, false) => ServicePermission.requestMovies,
  (DiscoveryMediaType.movie, true) => ServicePermission.request4kMovies,
  (DiscoveryMediaType.series, false) => ServicePermission.requestSeries,
  (DiscoveryMediaType.series, true) => ServicePermission.request4kSeries,
});

/// Why the variant of [title] is not offered to [user], or null if it is.
///
/// A series that is only partly there or asked for stays on offer: which of
/// its seasons can be requested is known with the seasons.
RequestBlock? requestBlock(
  DiscoveryTitle title,
  SessionUser user, {
  required bool is4k,
}) {
  final availability = is4k ? title.availability4k : title.availability;
  final status = is4k ? title.requestStatus4k : title.requestStatus;
  final isMovie = title.mediaType == DiscoveryMediaType.movie;
  if (availability.blocksRequest) return RequestBlock.blocklisted;
  if (availability == Availability.available ||
      isMovie && availability == Availability.partial) {
    return RequestBlock.available;
  }
  // The server takes one request for a movie until it is declined or done.
  if (isMovie &&
      (availability == Availability.pending ||
          availability == Availability.processing ||
          status == RequestStatus.pending ||
          status == RequestStatus.approved ||
          status == RequestStatus.failed)) {
    return RequestBlock.requested;
  }
  return mayRequest(user.permissions, title.mediaType, is4k: is4k)
      ? null
      : RequestBlock.notPermitted;
}

/// Whether anything is to be said about the 4K variant of [title]: most
/// servers have none.
bool shows4k(DiscoveryTitle title, SessionUser? user) =>
    title.availability4k != Availability.unknown ||
    title.requestStatus4k != null ||
    user != null && mayRequest(user.permissions, title.mediaType, is4k: true);
