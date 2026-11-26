/// Where a server task is.
enum CommandStatus {
  /// Waiting to run.
  queued,

  /// Running.
  started,

  /// Finished; see the result.
  completed,

  /// Failed.
  failed,

  /// Aborted.
  aborted,

  /// Cancelled.
  cancelled,

  /// Lost by the server.
  orphaned,

  /// A value the app does not know.
  unknown,
}
