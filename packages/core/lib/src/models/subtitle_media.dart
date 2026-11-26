import 'subtitle_kind.dart';

/// A movie, series or episode as the subtitle service knows it: by the ids of
/// the movie or series server it serves.
final class SubtitleMedia {
  /// A movie, by its Radarr id.
  const SubtitleMedia.movie(int this.radarrId)
    : kind = SubtitleKind.movie,
      seriesId = null,
      episodeId = null;

  /// A series, by its Sonarr id.
  const SubtitleMedia.series(int this.seriesId)
    : kind = SubtitleKind.series,
      episodeId = null,
      radarrId = null;

  /// An episode, by its Sonarr series and episode ids.
  const SubtitleMedia.episode({
    required int this.seriesId,
    required int this.episodeId,
  }) : kind = SubtitleKind.episode,
       radarrId = null;

  /// Movie, series or episode.
  final SubtitleKind kind;

  /// The series, for a series or episode.
  final int? seriesId;

  /// The episode.
  final int? episodeId;

  /// The movie.
  final int? radarrId;

  @override
  bool operator ==(Object other) =>
      other is SubtitleMedia &&
      other.kind == kind &&
      other.seriesId == seriesId &&
      other.episodeId == episodeId &&
      other.radarrId == radarrId;

  @override
  int get hashCode => Object.hash(kind, seriesId, episodeId, radarrId);
}
