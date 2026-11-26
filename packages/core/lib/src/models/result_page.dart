/// One page of a server-paged list.
final class ResultPage<T> {
  /// Creates a [ResultPage].
  const ResultPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  /// The items of this page.
  final List<T> items;

  /// Starts at 1.
  final int page;

  /// Whether another page follows.
  final bool hasMore;
}
