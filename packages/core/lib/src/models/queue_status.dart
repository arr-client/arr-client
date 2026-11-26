/// The state of a queue entry.
enum QueueStatus {
  /// Waiting in the client.
  queued,

  /// Paused.
  paused,

  /// Downloading.
  downloading,

  /// Held back by a delay setting.
  delayed,

  /// Downloaded.
  completed,

  /// The client reports a problem.
  warning,

  /// The download failed.
  failed,

  /// The server cannot reach the client.
  downloadClientUnavailable,

  /// Held for another protocol.
  fallback,

  /// A status the app does not know.
  unknown,
}
