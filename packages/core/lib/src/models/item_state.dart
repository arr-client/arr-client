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
  missing;

  /// The state of an item to which the given facts apply: where several do, the
  /// one that comes first in this enum wins.
  ///
  /// [allWantedPresent] is false for an item that wants no files, and
  /// [anyPresent] is true if the server has at least one of its files.
  static ItemState resolve({
    required bool downloading,
    required bool allWantedPresent,
    required bool anyPresent,
    required bool monitored,
    required bool released,
  }) {
    if (downloading) return ItemState.downloading;
    if (allWantedPresent) return ItemState.downloaded;
    if (anyPresent) return ItemState.partial;
    if (!monitored) return ItemState.unmonitored;
    if (!released) return ItemState.unreleased;
    return ItemState.missing;
  }
}
