/// A score from one source.
final class Rating {
  /// Creates a [Rating].
  const Rating({required this.source, required this.value, this.votes});

  /// Who rated.
  final String source;

  /// The score on the source's own scale.
  final double value;

  /// Number of votes.
  final int? votes;
}
