/// The state of a torrent in the download client.
enum DownloadState {
  /// Waiting to start.
  queued,

  /// Downloading.
  downloading,

  /// Paused.
  paused,

  /// No data is arriving.
  stalled,

  /// Verifying data.
  checking,

  /// Moving or preparing files.
  processing,

  /// Complete and uploading.
  seeding,

  /// Complete.
  completed,

  /// Failed.
  error,

  /// A state the app does not know.
  unknown,
}
