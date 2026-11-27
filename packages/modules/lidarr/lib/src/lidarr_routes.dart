/// Where the module's screens are, under `/instances/:instanceId/`.
library;

import 'package:core/core.dart';

/// The router pattern of an artist.
const artistPath = 'lidarr/artists/:artistId';

/// The router pattern of an album.
const albumPath = 'lidarr/albums/:albumId';

/// The screen of the artist or album [ref]. A track has none of its own: it is
/// listed on its album's.
ModuleRoute itemRoute(ItemRef ref) => switch (ref.kind) {
  MediaKind.artist => ModuleRoute(
    instanceId: ref.instanceId,
    path: 'lidarr/artists/${ref.remoteId}',
  ),
  MediaKind.album => ModuleRoute(
    instanceId: ref.instanceId,
    path: 'lidarr/albums/${ref.remoteId}',
  ),
  _ => throw ArgumentError.value(ref.kind, 'kind', 'no screen of Lidarr'),
};
