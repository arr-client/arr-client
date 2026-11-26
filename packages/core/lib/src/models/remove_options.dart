/// How to remove from the queue.
final class RemoveOptions {
  /// Creates a [RemoveOptions].
  const RemoveOptions({
    required this.removeFromClient,
    required this.blocklist,
    this.searchReplacement = false,
  });

  /// Also remove it from the download client.
  final bool removeFromClient;

  /// Block the release.
  final bool blocklist;

  /// Only matters when [blocklist] is true.
  final bool searchReplacement;
}
