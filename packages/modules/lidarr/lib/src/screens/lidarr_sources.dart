import 'package:core/core.dart';

/// What the screens of one instance read and open.
///
/// Compared by identity, so one object serves an instance for as long as it is
/// connected: the screens' state is kept under it.
final class LidarrSources {
  /// Creates the [LidarrSources] of an instance.
  LidarrSources({
    required this.instanceId,
    required this.library,
    required this.history,
    required this.commands,
    required this.artwork,
    required this.navigator,
    this.removals = const Stream.empty(),
  });

  /// The instance.
  final String instanceId;

  /// Its artists, albums and tracks.
  final LibraryProvider library;

  /// Its history.
  final HistoryProvider history;

  /// Starts and follows its tasks.
  final CommandProvider commands;

  /// Loads its artwork.
  final ArtworkLoader artwork;

  /// Opens shared flows of the app.
  final AppNavigator navigator;

  /// The instance's items found to be gone from the server.
  final Stream<ItemRef> removals;

  /// The key of the artist [id].
  ItemRef artist(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.artist, remoteId: id);

  /// The key of the album [id].
  ItemRef album(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.album, remoteId: id);
}
