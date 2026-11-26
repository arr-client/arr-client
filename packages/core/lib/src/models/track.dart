part of 'library_item.dart';

/// A track of an album.
final class Track extends LibraryItem {
  /// Creates a [Track].
  const Track({
    required super.ref,
    required super.title,
    required super.sortTitle,
    required super.monitored,
    required super.state,
    required this.trackNumber,
    required this.discNumber,
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
    this.duration,
    this.file,
  });

  /// Number as printed, which need not be numeric.
  final String trackNumber;

  /// Disc.
  final int discNumber;

  /// Playing time.
  final Duration? duration;

  /// Whether the server has a file.
  final bool hasFile;

  /// The file, where loaded.
  final MediaFile? file;
}
