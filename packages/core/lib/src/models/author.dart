part of 'library_item.dart';

/// An author.
final class Author extends LibraryItem {
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
    this.metadataProfileId,
    this.books = const [],
  });

  final int? metadataProfileId;
  final List<Book> books;
}
