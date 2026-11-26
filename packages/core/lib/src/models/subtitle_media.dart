import 'subtitle_kind.dart';

/// A movie, series or episode as the subtitle service knows it: by the ids of
/// the movie or series server it serves.
final class SubtitleMedia {
  const SubtitleMedia.movie(int this.radarrId)
    : kind = SubtitleKind.movie,
      seriesId = null,
      episodeId = null;

  const SubtitleMedia.series(int this.seriesId)
    : kind = SubtitleKind.series,
      episodeId = null,
      radarrId = null;

  const SubtitleMedia.episode({
    required int this.seriesId,
    required int this.episodeId,
  }) : kind = SubtitleKind.episode,
       radarrId = null;

  final SubtitleKind kind;
  final int? seriesId;
  final int? episodeId;
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
