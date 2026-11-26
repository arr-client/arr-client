/// An edition of a book.
final class Edition {
  const Edition({
    required this.title,
    required this.monitored,
    this.format,
    this.isbn,
    this.pageCount,
    this.releaseDate,
  });

  final String title;

  final String? format;

  final String? isbn;

  final int? pageCount;

  final DateTime? releaseDate;

  final bool monitored;
}
