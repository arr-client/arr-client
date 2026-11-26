/// Where the module's screens are, under `/instances/:instanceId/`.
library;

import 'package:core/core.dart';

/// The router pattern of a series.
const seriesPath = 'sonarr/series/:seriesId';

/// The router pattern of one season of a series.
const seasonPath = 'sonarr/series/:seriesId/seasons/:season';

/// The router pattern of an episode.
const episodePath = 'sonarr/episodes/:episodeId';

/// The screen of the series or episode [ref].
ModuleRoute itemRoute(ItemRef ref) => switch (ref.kind) {
  MediaKind.series => ModuleRoute(
    instanceId: ref.instanceId,
    path: 'sonarr/series/${ref.remoteId}',
  ),
  MediaKind.episode => ModuleRoute(
    instanceId: ref.instanceId,
    path: 'sonarr/episodes/${ref.remoteId}',
  ),
  _ => throw ArgumentError.value(ref.kind, 'kind', 'no screen of Sonarr'),
};

/// The screen of season [number] of [series]. A season is no item of its own,
/// so it has no [ItemRef].
ModuleRoute seasonRoute(ItemRef series, int number) => ModuleRoute(
  instanceId: series.instanceId,
  path: 'sonarr/series/${series.remoteId}/seasons/$number',
);
