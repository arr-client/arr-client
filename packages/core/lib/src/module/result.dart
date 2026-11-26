/// The outcome of an operation that can fail in an expected way.
///
/// Consume it with an exhaustive `switch` over [Ok] and [Err].
sealed class Result<T, E> {
  const Result();
}

/// The operation succeeded with [value].
final class Ok<T, E> extends Result<T, E> {
  /// Creates an [Ok].
  const Ok(this.value);

  /// What the operation produced.
  final T value;
}

/// The operation failed with [error].
final class Err<T, E> extends Result<T, E> {
  /// Creates an [Err].
  const Err(this.error);

  /// Why it failed.
  final E error;
}
