/// The state of a torrent in the download client.
enum DownloadState {
  queued,
  downloading,
  paused,
  stalled,
  checking,
  processing,
  seeding,
  completed,
  error,
  unknown,
}
