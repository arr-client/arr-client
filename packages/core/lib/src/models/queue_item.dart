import 'download_protocol.dart';
import 'item_ref.dart';
import 'quality.dart';
import 'queue_severity.dart';
import 'queue_status.dart';
import 'tracked_state.dart';

/// An entry of the download queue.
final class QueueItem {
  /// Creates a [QueueItem].
  const QueueItem({
    required this.id,
    required this.title,
    required this.status,
    required this.trackedState,
    required this.severity,
    required this.progress,
    required this.sizeLeft,
    required this.protocol,
    this.downloadId,
    this.itemRef,
    this.parent,
    this.eta,
    this.quality,
    this.downloadClient,
    this.messages = const [],
    this.needsManualImport = false,
  }) : assert(progress >= 0 && progress <= 1, 'progress is from 0 to 1');

  /// [progress] for a download of [size] bytes with [sizeLeft] still to come.
  /// It is 0 while the size is not known.
  static double progressFrom({required num size, required num sizeLeft}) {
    if (!(size > 0)) return 0;
    final fraction = (size - sizeLeft) / size;
    return fraction.isNaN ? 0 : fraction.clamp(0, 1).toDouble();
  }

  /// The server's id of the queue entry.
  final int id;

  /// The download client's id, used to match its progress.
  final String? downloadId;

  /// The item being downloaded; null if the server cannot match it.
  final ItemRef? itemRef;

  /// The series, artist or author [itemRef] belongs to, so that its screen can
  /// find its queue entries.
  final ItemRef? parent;

  /// The release's title.
  final String title;

  /// The state of the entry.
  final QueueStatus status;

  /// How far the server is with handling it.
  final TrackedState trackedState;

  /// Independent of [status]: a completed download can carry a warning.
  final QueueSeverity severity;

  /// The server's reasons for warnings and errors.
  final List<String> messages;

  /// From 0 to 1.
  final double progress;

  /// Bytes.
  final int sizeLeft;

  /// Estimated time left.
  final Duration? eta;

  /// Quality of the release.
  final Quality? quality;

  /// Name of the download client.
  final String? downloadClient;

  /// How it is downloaded.
  final DownloadProtocol protocol;

  /// Whether it waits for a manual import.
  final bool needsManualImport;
}
