import 'package:core/core.dart';

/// Whether the server is holding the release back and has downloaded nothing.
bool isWaitingRelease(QueueItem item) =>
    (item.downloadId?.isEmpty ?? true) &&
    switch (item.status) {
      QueueStatus.delayed ||
      QueueStatus.downloadClientUnavailable ||
      QueueStatus.fallback => true,
      _ => false,
    };

/// Equal for the entries that the server removes or grabs together: those of
/// one download, and those waiting for one release. A waiting season pack has
/// an entry for each episode and nothing that names it but its title.
Object queueGroup(QueueItem item) {
  final download = item.downloadId;
  if (download != null && download.isNotEmpty) return (download: download);
  if (isWaitingRelease(item) && item.title.isNotEmpty) {
    return (title: item.title, parent: item.parent, protocol: item.protocol);
  }
  return (id: item.id);
}
