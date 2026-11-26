part of 'library_item.dart';

/// An author.
final class Author extends LibraryItem {
  /// Creates an [Author].
  const Author({
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
    this.metadataProfileId,
    this.books = const [],
  });

  /// The author's metadata profile.
  final int? metadataProfileId;

  /// The author's books.
  final List<Book> books;
}
