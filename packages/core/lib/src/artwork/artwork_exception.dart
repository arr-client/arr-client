/// A piece of artwork could not be loaded. It carries no address, as Flutter
/// prints the errors of images.
final class ArtworkException implements Exception {
  /// Creates an [ArtworkException].
  const ArtworkException(this.reason, {this.gone = false});

  /// What went wrong, without addresses or secrets.
  final String reason;

  /// Whether the server says that there is no such artwork any more.
  final bool gone;

  @override
  String toString() => 'ArtworkException: $reason';
}
