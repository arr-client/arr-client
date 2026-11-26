import 'download_protocol.dart';

/// An indexer, read only.
final class Indexer {
  const Indexer({
    required this.id,
    required this.name,
    required this.protocol,
    required this.enabled,
    this.failureUntil,
    this.lastFailure,
  });

  final int id;

  final String name;

  final DownloadProtocol protocol;

  final bool enabled;

  final DateTime? failureUntil;

  final DateTime? lastFailure;
}
