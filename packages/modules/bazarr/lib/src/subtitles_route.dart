/// Where the module's screens are, under `/instances/:instanceId/`.
library;

import 'package:core/core.dart';

/// The router pattern of the subtitle screen.
const subtitlesPattern = 'bazarr/subtitles';

/// The router pattern of a movie.
const moviePattern = '$subtitlesPattern/movies/:radarrId';

/// The router pattern of a series, which lists its episodes.
const seriesPattern = '$subtitlesPattern/series/:seriesId';

/// The router pattern of an episode.
const episodePattern = '$seriesPattern/episodes/:episodeId';

/// The router pattern of a manual search for a movie.
const movieSearchPattern = '$moviePattern/search';

/// The router pattern of a manual search for an episode.
const episodeSearchPattern = '$episodePattern/search';

String _path(SubtitleMedia media) => switch (media.kind) {
  SubtitleKind.movie => '$subtitlesPattern/movies/${media.radarrId}',
  SubtitleKind.series => '$subtitlesPattern/series/${media.seriesId}',
  SubtitleKind.episode =>
    '$subtitlesPattern/series/${media.seriesId}/episodes/${media.episodeId}',
};

/// The screen of [media] on the instance [instanceId].
ModuleRoute mediaRoute(String instanceId, SubtitleMedia media) =>
    ModuleRoute(instanceId: instanceId, path: _path(media));

/// The manual search for the movie or episode [media].
ModuleRoute searchRoute(String instanceId, SubtitleMedia media) =>
    ModuleRoute(instanceId: instanceId, path: '${_path(media)}/search');
