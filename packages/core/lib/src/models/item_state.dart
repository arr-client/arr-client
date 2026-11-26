/// A library item's state, declared from highest to lowest precedence.
enum ItemState {
  /// In the queue.
  downloading,

  /// All wanted files are present.
  downloaded,

  /// Some files are present.
  partial,

  /// Not monitored.
  unmonitored,

  /// Not released yet.
  unreleased,

  /// Wanted and absent.
  missing,
}
