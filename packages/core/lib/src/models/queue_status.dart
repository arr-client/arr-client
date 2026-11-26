/// The state of a queue entry.
enum QueueStatus {
  queued,
  paused,
  downloading,
  delayed,
  completed,
  warning,
  failed,
  downloadClientUnavailable,
  fallback,
  unknown,
}
