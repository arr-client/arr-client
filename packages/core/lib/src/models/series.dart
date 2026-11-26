part of 'library_item.dart';

/// A series.
final class Series extends LibraryItem {
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

  final SeriesType seriesType;
  final bool seasonFolder;
  final String? network;
  final SeriesStatus status;
  final Duration? runtime;
  final List<String> genres;
  final String? certification;
  final List<Rating> ratings;
  final List<Season> seasons;
}
