/// The state of the screens, kept while a screen that reads it is open.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'cached_item_controller.dart';
import 'lidarr_sources.dart';

/// One item of one instance.
typedef ItemKey = (LidarrSources, ItemRef);

/// An artist.
final artistProvider = NotifierProvider.autoDispose
    .family<ArtistController, ViewState<Artist>, ItemKey>(ArtistController.new);

/// The albums of an artist.
final albumsProvider = NotifierProvider.autoDispose
    .family<AlbumsController, ViewState<List<Album>>, ItemKey>(
      AlbumsController.new,
    );

/// An album.
final albumProvider = NotifierProvider.autoDispose
    .family<AlbumController, ViewState<Album>, ItemKey>(AlbumController.new);

/// The tracks of an album.
final tracksProvider = NotifierProvider.autoDispose
    .family<TracksController, ViewState<List<Track>>, ItemKey>(
      TracksController.new,
    );

/// The albums of one instance whose [albumProvider] is alive: those of the
/// screens open, also beneath others. A change to an artist has them read
/// again.
final openAlbumsProvider = Provider.family<Set<ItemRef>, LidarrSources>(
  (ref, sources) => {},
);

/// The server's quality profiles, metadata profiles and tags, by whose ids an
/// artist names them: those saved first, then those the server gives. Empty
/// where there are neither: the screen then leaves the names out.
final optionsProvider = StreamProvider.autoDispose
    .family<List<ServerOption>, LidarrSources>((ref, sources) async* {
      final saved = switch (await sources.library.cachedOptions()) {
        Ok(value: Cached(:final value)) => value,
        _ => null,
      };
      if (saved != null) yield saved;
      switch (await sources.library.options()) {
        case Ok(:final value):
          yield value;
        case Err():
          if (saved == null) yield const [];
      }
    });

/// The newest events of an artist or album.
final historyProvider = FutureProvider.autoDispose
    .family<Result<ResultPage<HistoryEvent>, ServiceFailure>, ItemKey>(
      (ref, key) => key.$1.history.history(target: MediaTarget(key.$2)),
    );

Result<T, ServiceFailure> _item<T extends LibraryItem>(
  Result<LibraryItem, ServiceFailure> result,
) => switch (result) {
  Ok(value: final T item) => Ok(item),
  Ok() => const Err(MalformedResponse()),
  Err(:final error) => Err(error),
};

ServiceResult<Cached<T>?> _cachedItem<T extends LibraryItem>(
  ItemKey key,
) async => switch (await key.$1.library.cachedItem(key.$2)) {
  Ok(value: Cached(value: final T item, :final fetchedAt)) => Ok(
    Cached(item, fetchedAt: fetchedAt),
  ),
  Ok() => const Ok(null),
  Err(:final error) => Err(error),
};

ServiceResult<Cached<List<T>>?> _cachedChildren<T extends LibraryItem>(
  ItemKey key,
) async => switch (await key.$1.library.cachedChildren(key.$2)) {
  Ok(value: Cached(:final value, :final fetchedAt)) => Ok(
    Cached(value.whereType<T>().toList(), fetchedAt: fetchedAt),
  ),
  Ok() => const Ok(null),
  Err(:final error) => Err(error),
};

ServiceResult<List<T>> _children<T extends LibraryItem>(ItemKey key) async =>
    switch (await key.$1.library.children(key.$2)) {
      Ok(:final value) => Ok(value.whereType<T>().toList()),
      Err(:final error) => Err(error),
    };

/// What is left of a list of children of [parent] now that [gone] is.
ViewState<List<T>>? _without<T extends LibraryItem>(
  ViewState<List<T>> shown,
  ItemRef gone,
  ItemRef parent,
) {
  if (gone == parent) return const ViewError(NotFound());
  if (shown case ViewData(:final value, :final staleness)
      when value.any((item) => item.ref == gone)) {
    return ViewData([
      for (final item in value)
        if (item.ref != gone) item,
    ], staleness: staleness);
  }
  return null;
}

/// Holds one artist.
final class ArtistController extends CachedItemController<Artist> {
  /// For the artist [key].
  ArtistController(this.key);

  /// The artist.
  final ItemKey key;

  @override
  ServiceResult<Cached<Artist>?> readCached() => _cachedItem(key);

  @override
  ServiceResult<Artist> fetch() async =>
      _item(await key.$1.library.item(key.$2));

  @override
  Stream<ItemRef> get removals => key.$1.removals;

  @override
  ViewState<Artist>? without(ViewState<Artist> shown, ItemRef gone) =>
      gone == key.$2 ? const ViewError(NotFound()) : null;
}

/// Holds the albums of one artist.
final class AlbumsController extends CachedItemController<List<Album>> {
  /// For the artist [key].
  AlbumsController(this.key);

  /// The artist.
  final ItemKey key;

  @override
  ServiceResult<Cached<List<Album>>?> readCached() => _cachedChildren(key);

  @override
  ServiceResult<List<Album>> fetch() => _children(key);

  @override
  Stream<ItemRef> get removals => key.$1.removals;

  @override
  ViewState<List<Album>>? without(ViewState<List<Album>> shown, ItemRef gone) =>
      _without(shown, gone, key.$2);
}

/// Holds one album.
final class AlbumController extends CachedItemController<Album> {
  /// For the album [key].
  AlbumController(this.key);

  /// The album.
  final ItemKey key;

  @override
  ViewState<Album> build() {
    final open = ref.read(openAlbumsProvider(key.$1))..add(key.$2);
    ref.onDispose(() => open.remove(key.$2));
    return super.build();
  }

  @override
  ServiceResult<Cached<Album>?> readCached() => _cachedItem(key);

  @override
  ServiceResult<Album> fetch() async =>
      _item(await key.$1.library.item(key.$2));

  @override
  Stream<ItemRef> get removals => key.$1.removals;

  // An album goes with its artist.
  @override
  ViewState<Album>? without(ViewState<Album> shown, ItemRef gone) {
    final artist = shown is ViewData<Album> ? shown.value.parent : null;
    return gone == key.$2 || gone == artist
        ? const ViewError(NotFound())
        : null;
  }
}

/// Holds the tracks of one album.
final class TracksController extends CachedItemController<List<Track>> {
  /// For the album [key].
  TracksController(this.key);

  /// The album.
  final ItemKey key;

  @override
  ServiceResult<Cached<List<Track>>?> readCached() => _cachedChildren(key);

  @override
  ServiceResult<List<Track>> fetch() => _children(key);

  @override
  Stream<ItemRef> get removals => key.$1.removals;

  @override
  ViewState<List<Track>>? without(ViewState<List<Track>> shown, ItemRef gone) =>
      _without(shown, gone, key.$2);
}
