/// How to remove from the queue.
final class RemoveOptions {
  const RemoveOptions({
    required this.removeFromClient,
    required this.blocklist,
    this.searchReplacement = false,
  });

  final bool removeFromClient;

  final bool blocklist;

  /// Only matters when [blocklist] is true.
  final bool searchReplacement;
}
