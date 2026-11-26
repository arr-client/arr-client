import 'package:core/core.dart';

/// What the screens of one instance read and open.
///
/// Compared by identity, so one object serves an instance for as long as it is
/// connected: the screens' state is kept under it.
final class SonarrSources {
  /// Creates the [SonarrSources] of an instance.
  SonarrSources({
    required this.instanceId,
    required this.library,
    required this.history,
    required this.artwork,
    required this.navigator,
    this.removals = const Stream.empty(),
  });

  /// The instance.
  final String instanceId;

  /// Its series and episodes.
  final LibraryProvider library;

  /// Its history.
  final HistoryProvider history;

  /// Loads its artwork.
  final ArtworkLoader artwork;

  /// Opens shared flows of the app.
  final AppNavigator navigator;

  /// The instance's items found to be gone from the server.
  final Stream<ItemRef> removals;

  /// The key of the series [id].
  ItemRef series(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.series, remoteId: id);

  /// The key of the episode [id].
  ItemRef episode(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.episode, remoteId: id);
}
