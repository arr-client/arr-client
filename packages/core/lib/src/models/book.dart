part of 'library_item.dart';

/// A book.
final class Book extends LibraryItem {
  const Book({
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
    this.seriesTitle,
    this.editions = const [],
    this.files = const [],
  });

  final String? seriesTitle;
  final List<Edition> editions;
  final List<MediaFile> files;
}
