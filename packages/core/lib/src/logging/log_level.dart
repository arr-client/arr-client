/// How serious a log entry is.
enum LogLevel {
  /// Detail for finding a fault.
  debug,

  /// Normal events.
  info,

  /// Something unexpected that was handled.
  warning,

  /// A failure.
  error,
}
