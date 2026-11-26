part of 'library_item.dart';

/// An episode of a series.
final class Episode extends LibraryItem {
  const Episode({
    required super.ref,
    required super.title,
    required super.sortTitle,
    required super.monitored,
    required super.state,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.hasFile,
    super.year,
    super.overview,
    super.images,
    super.qualityProfileId,
    super.tagIds,
    super.path,
    super.sizeOnDisk,
    super.addedAt,
    this.airDateUtc,
    this.file,
  });

  final int seasonNumber;
  final int episodeNumber;
  final DateTime? airDateUtc;
  final bool hasFile;
  final MediaFile? file;
}
