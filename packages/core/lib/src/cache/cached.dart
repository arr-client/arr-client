/// Records read from the cache, with their age.
final class Cached<T> {
  /// Creates a [Cached].
  const Cached(this.value, {required this.fetchedAt});

  /// The records as last fetched.
  final T value;

  /// When the server was last asked.
  final DateTime fetchedAt;
}
