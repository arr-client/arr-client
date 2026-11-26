/// Whether the server reports a problem with a queue entry.
enum QueueSeverity {
  /// No problem.
  ok,

  /// Needs attention.
  warning,

  /// Failed.
  error,

  /// A value the app does not know.
  unknown,
}
