import 'download_protocol.dart';
import 'item_ref.dart';
import 'quality.dart';
import 'queue_status.dart';
import 'tracked_state.dart';

/// An entry of the download queue.
final class QueueItem {
  const QueueItem({
    required this.id,
    required this.title,
    required this.status,
    required this.trackedState,
    required this.progress,
    required this.sizeLeft,
    required this.protocol,
    this.downloadId,
    this.itemRef,
    this.eta,
    this.quality,
    this.downloadClient,
    this.messages = const [],
    this.needsManualImport = false,
  });

  final int id;

  final String? downloadId;

  final ItemRef? itemRef;

  final String title;

  final QueueStatus status;

  final TrackedState trackedState;

  final List<String> messages;

  /// From 0 to 1.
  final double progress;

  /// Bytes.
  final int sizeLeft;

  final Duration? eta;

  final Quality? quality;

  final String? downloadClient;

  final DownloadProtocol protocol;

  final bool needsManualImport;
}
