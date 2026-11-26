/// A score from one source.
final class Rating {
  const Rating({required this.source, required this.value, this.votes});

  final String source;

  final double value;

  final int? votes;
}
