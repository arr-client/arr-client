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

/// The server's quality profiles and tags, by whose ids a series names them.
/// Empty where they cannot be read: the screen then leaves the names out.
final optionsProvider = FutureProvider.autoDispose
    .family<List<ServerOption>, SonarrSources>(
      (ref, sources) async => switch (await sources.library.options()) {
        Ok(:final value) => value,
        Err() => const [],
      },
    );

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
}
