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
  /// An item's parts are what holds its files: a movie itself, or a series'
  /// episodes. Wanted does not mean monitored. If [monitored] is true, the
  /// wanted files are those of the released, monitored parts and any already
  /// present. If it is false, they are those of every released part and any
  /// already present. So a movie with its file is downloaded whether or not it
  /// is monitored, and an unmonitored series that lacks released episodes is
  /// partial, not downloaded.
  ///
  /// [allWantedPresent] is true if there is at least one wanted file and none is
  /// absent. [anyPresent] is true if the server has at least one of the item's
  /// files.
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
