import '../models/download_progress.dart';
import '../models/queue_item.dart';

/// The download client's figures for [item], or null if no torrent is its
/// download.
///
/// [torrents] holds what every download client instance of the active profile
/// reported, one instance after another in instance order. The first torrent
/// whose `hash` or `infohashV1` equals the item's `downloadId`, ignoring case,
/// is the match. Queue entries that share a download id, such as those of a
/// season pack, get the same record, whose figures are for the whole torrent.
DownloadProgress? matchProgress(
  QueueItem item,
  Iterable<DownloadProgress> torrents,
) {
  final id = item.downloadId?.toLowerCase();
  if (id == null || id.isEmpty) return null;
  for (final torrent in torrents) {
    if (torrent.hash.toLowerCase() == id ||
        torrent.infohashV1?.toLowerCase() == id) {
      return torrent;
    }
  }
  return null;
}
