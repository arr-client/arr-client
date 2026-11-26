import 'download_state.dart';

/// A download client's figures for one torrent. Not persisted.
final class DownloadProgress {
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

  final String hash;

  final String? infohashV1;

  /// From 0 to 1.
  final double progress;

  /// Bytes per second.
  final int downSpeed;

  final Duration? eta;

  final DownloadState state;
}
