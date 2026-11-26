/// Where a server task is.
enum CommandStatus {
  queued,
  started,
  completed,
  failed,
  aborted,
  cancelled,
  orphaned,
  unknown,
}
