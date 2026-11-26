/// Where a series is in its run.
enum SeriesStatus {
  /// Still running.
  continuing,

  /// Ended.
  ended,

  /// Not started.
  upcoming,

  /// Removed from the metadata source.
  deleted,

  /// A status the app does not know.
  unknown,
}
