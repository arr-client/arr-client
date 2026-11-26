/// An edition of a book.
final class Edition {
  /// Creates an [Edition].
  const Edition({
    required this.title,
    required this.monitored,
    this.format,
    this.isbn,
    this.pageCount,
    this.releaseDate,
  });

  /// The edition's title.
  final String title;

  /// Such as hardcover or ebook.
  final String? format;

  /// ISBN.
  final String? isbn;

  /// Number of pages.
  final int? pageCount;

  /// When it was released.
  final DateTime? releaseDate;

  /// Whether this edition is monitored.
  final bool monitored;
}
