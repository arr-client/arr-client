part of 'library_item.dart';

/// A series.
final class Series extends LibraryItem {
  /// Creates a [Series].
  const Series({
    required super.ref,
    required super.title,
    required super.sortTitle,
    required super.monitored,
    required super.state,
    super.year,
    super.overview,
    super.images,
    super.qualityProfileId,
    super.tagIds,
    super.path,
    super.sizeOnDisk,
    super.addedAt,
    super.parent,
    super.parentTitle,
    this.network,
    this.runtime,
    this.certification,
    this.seriesType = SeriesType.unknown,
    this.seasonFolder = false,
    this.status = SeriesStatus.unknown,
    this.genres = const [],
    this.ratings = const [],
    this.seasons = const [],
  });

  /// How episodes are numbered.
  final SeriesType seriesType;

  /// Whether episodes go into season folders.
  final bool seasonFolder;

  /// Network.
  final String? network;

  /// Where the series is in its run.
  final SeriesStatus status;

  /// Usual episode length.
  final Duration? runtime;

  /// Genres.
  final List<String> genres;

  /// Age rating.
  final String? certification;

  /// Scores.
  final List<Rating> ratings;

  /// Seasons.
  final List<Season> seasons;
}
