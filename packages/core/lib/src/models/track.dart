part of 'library_item.dart';

/// A track of an album.
final class Track extends LibraryItem {
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
    this.duration,
    this.file,
  });

  final String trackNumber;
  final int discNumber;
  final Duration? duration;
  final bool hasFile;
  final MediaFile? file;
}
