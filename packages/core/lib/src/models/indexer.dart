import 'download_protocol.dart';

/// An indexer, read only.
final class Indexer {
  /// Creates an [Indexer].
  const Indexer({
    required this.id,
    required this.name,
    required this.protocol,
    required this.enabled,
    this.failureUntil,
    this.lastFailure,
  });

  /// The server's id of the indexer.
  final int id;

  /// Its name.
  final String name;

  /// What it indexes.
  final DownloadProtocol protocol;

  /// Whether the server uses it.
  final bool enabled;

  /// Until when the server avoids it after failures.
  final DateTime? failureUntil;

  /// When it last failed.
  final DateTime? lastFailure;
}
