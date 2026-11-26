part of 'library_item.dart';

/// A book.
final class Book extends LibraryItem {
  /// Creates a [Book].
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
    super.parent,
    super.parentTitle,
    this.seriesTitle,
    this.editions = const [],
    this.files = const [],
  });

  /// The book series it is part of.
  final String? seriesTitle;

  /// Known editions.
  final List<Edition> editions;

  /// Files on the server.
  final List<MediaFile> files;
}
