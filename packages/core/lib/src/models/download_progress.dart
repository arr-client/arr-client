import 'download_state.dart';

/// A download client's figures for one torrent. Not persisted.
final class DownloadProgress {
  /// Creates a [DownloadProgress].
  const DownloadProgress({
    required this.instanceId,
    required this.hash,
    required this.progress,
    required this.downSpeed,
    required this.state,
    this.infohashV1,
    this.eta,
  });

  /// The download client's instance.
  final String instanceId;

  /// The torrent's hash.
  final String hash;

  /// The version 1 info hash, where it differs from [hash].
  final String? infohashV1;

  /// From 0 to 1.
  final double progress;

  /// Bytes per second.
  final int downSpeed;

  /// Estimated time left.
  final Duration? eta;

  /// What the torrent is doing.
  final DownloadState state;
}
