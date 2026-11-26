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

  /// Nothing wanted is released yet.
  unreleased,

  /// Wanted and absent.
  missing;

  /// The state of an item to which the given facts apply: where several do, the
  /// one that comes first in this enum wins.
  ///
  /// Where the facts come from depends on the item. A movie, episode, track or
  /// book holds its own file, and is itself what is wanted. A series, artist,
  /// author or album is a container: what it wants is what the server counts in
  /// its statistics (`episodeCount`, `trackCount`, `bookCount`), which is the
  /// parts that are released and monitored plus any with a file. The
  /// container's own monitored flag does not change that count.
  ///
  /// | Fact | Item with its own file | Container |
  /// |---|---|---|
  /// | [allWantedPresent] | has its file | wants some, and all have files |
  /// | [anyPresent] | has its file | some part has a file |
  /// | [monitored] | its own flag | its own flag |
  /// | [released] | is released | wants at least one released part |
  ///
  /// A track is monitored when its album is.
  ///
  /// So a movie with its file is downloaded whether or not it is monitored. A
  /// container that wants nothing has no files either: it is unmonitored if its
  /// flag is off, and otherwise unreleased, as is a monitored series set to
  /// future episodes only before any of them is released.
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
