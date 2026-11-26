/// One page of a server-paged list.
final class ResultPage<T> {
  const ResultPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<T> items;

  /// Starts at 1.
  final int page;

  final bool hasMore;
}
