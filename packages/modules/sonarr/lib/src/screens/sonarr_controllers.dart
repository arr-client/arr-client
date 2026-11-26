/// The state of the screens, kept while a screen that reads it is open.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'cached_item_controller.dart';
import 'sonarr_sources.dart';

/// One item of one instance.
typedef ItemKey = (SonarrSources, ItemRef);

/// A series.
final seriesProvider = NotifierProvider.autoDispose
    .family<SeriesController, ViewState<Series>, ItemKey>(SeriesController.new);

/// The episodes of a series.
final episodesProvider = NotifierProvider.autoDispose
    .family<EpisodesController, ViewState<List<Episode>>, ItemKey>(
      EpisodesController.new,
    );

/// An episode.
final episodeProvider = NotifierProvider.autoDispose
    .family<EpisodeController, ViewState<Episode>, ItemKey>(
      EpisodeController.new,
    );

/// The server's quality profiles and tags, by whose ids a series names them:
/// those saved first, then those the server gives. Empty where there are
/// neither: the screen then leaves the names out.
final optionsProvider = StreamProvider.autoDispose
    .family<List<ServerOption>, SonarrSources>((ref, sources) async* {
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

/// The newest events of a series or episode.
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

List<Episode> _episodes(List<LibraryItem> items) =>
    items.whereType<Episode>().toList();

/// Holds one series.
final class SeriesController extends CachedItemController<Series> {
  /// For the series [key].
  SeriesController(this.key);

  /// The series.
  final ItemKey key;

  @override
  ServiceResult<Cached<Series>?> readCached() => _cachedItem(key);

  @override
  ServiceResult<Series> fetch() async =>
      _item(await key.$1.library.item(key.$2));

  @override
  Stream<ItemRef> get removals => key.$1.removals;

  @override
  ViewState<Series>? without(ViewState<Series> shown, ItemRef gone) =>
      gone == key.$2 ? const ViewError(NotFound()) : null;
}

/// Holds the episodes of one series.
final class EpisodesController extends CachedItemController<List<Episode>> {
  /// For the series [key].
  EpisodesController(this.key);

  /// The series.
  final ItemKey key;

  @override
  ServiceResult<Cached<List<Episode>>?> readCached() async =>
      switch (await key.$1.library.cachedChildren(key.$2)) {
        Ok(value: Cached(:final value, :final fetchedAt)) => Ok(
          Cached(_episodes(value), fetchedAt: fetchedAt),
        ),
        Ok() => const Ok(null),
        Err(:final error) => Err(error),
      };

  @override
  ServiceResult<List<Episode>> fetch() async =>
      switch (await key.$1.library.children(key.$2)) {
        Ok(:final value) => Ok(_episodes(value)),
        Err(:final error) => Err(error),
      };

  @override
  Stream<ItemRef> get removals => key.$1.removals;

  @override
  ViewState<List<Episode>>? without(
    ViewState<List<Episode>> shown,
    ItemRef gone,
  ) {
    if (gone == key.$2) return const ViewError(NotFound());
    if (shown case ViewData(:final value, :final staleness)
        when value.any((episode) => episode.ref == gone)) {
      return ViewData([
        for (final episode in value)
          if (episode.ref != gone) episode,
      ], staleness: staleness);
    }
    return null;
  }
}

/// Holds one episode.
final class EpisodeController extends CachedItemController<Episode> {
  /// For the episode [key].
  EpisodeController(this.key);

  /// The episode.
  final ItemKey key;

  @override
  ServiceResult<Cached<Episode>?> readCached() => _cachedItem(key);

  @override
  ServiceResult<Episode> fetch() async =>
      _item(await key.$1.library.item(key.$2));

  @override
  Stream<ItemRef> get removals => key.$1.removals;

  // An episode goes with its series.
  @override
  ViewState<Episode>? without(ViewState<Episode> shown, ItemRef gone) {
    final series = shown is ViewData<Episode> ? shown.value.parent : null;
    return gone == key.$2 || gone == series
        ? const ViewError(NotFound())
        : null;
  }
}
