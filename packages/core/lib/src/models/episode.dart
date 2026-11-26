part of 'library_item.dart';

/// An episode of a series.
final class Episode extends LibraryItem {
  /// Creates an [Episode].
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
    super.parent,
    super.parentTitle,
    this.airDateUtc,
    this.file,
  });

  /// The season; 0 holds specials.
  final int seasonNumber;

  /// The number within the season.
  final int episodeNumber;

  /// When it airs or aired, UTC.
  final DateTime? airDateUtc;

  /// Whether the server has a file.
  final bool hasFile;

  /// The file, where loaded.
  final MediaFile? file;
}
