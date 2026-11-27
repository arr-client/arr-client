/// The server-paged lists of the subtitle screen: wanted, history and titles.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'bazarr_source.dart';

/// One kind of list of an instance: of movies, or of episodes. The titles of
/// [SubtitleMediaType.episode] are the series.
typedef ListKey = ({BazarrSource source, SubtitleMediaType type});

/// The pages read of a list.
@immutable
final class Pages<T> {
  /// Creates [Pages].
  const Pages({
    required this.items,
    required this.pages,
    required this.hasMore,
    this.loadingMore = false,
    this.moreFailure,
  });

  /// In the server's order.
  final List<T> items;

  /// How many pages [items] are.
  final int pages;

  /// Whether the server has more.
  final bool hasMore;

  /// Whether the next page is being read.
  final bool loadingMore;

  /// Why the next page could not be read.
  final ServiceFailure? moreFailure;

  Pages<T> _with({bool loadingMore = false, ServiceFailure? moreFailure}) =>
      Pages(
        items: items,
        pages: pages,
        hasMore: hasMore,
        loadingMore: loadingMore,
        moreFailure: moreFailure,
      );
}

/// Reads a list a page at a time, as the user asks for more. What was read
/// stays, with its age, while it is read again and if that fails.
abstract class PagedController<T> extends Notifier<ViewState<Pages<T>>> {
  DateTime _fetchedAt = DateTime.now();
  var _reads = 0;

  /// Asks for page [number], from 1.
  ServiceResult<ResultPage<T>> fetch(int number);

  /// What makes an item the same one, as a list can change between pages,
  /// which then repeat items. Null keeps every item.
  Object? identify(T item) => null;

  @override
  ViewState<Pages<T>> build() {
    // Not at once: there is no state to change until this returns.
    unawaited(Future.microtask(() => _read(1)));
    return const ViewLoading();
  }

  /// Reads again the pages already read.
  Future<void> reload() {
    var upTo = 1;
    switch (state) {
      case ViewData(:final value):
        upTo = value.pages;
        state = ViewData(
          value._with(),
          staleness: Staleness(fetchedAt: _fetchedAt),
        );
      case ViewError():
        state = const ViewLoading();
      case ViewLoading():
        break;
    }
    return _read(upTo);
  }

  Future<void> _read(int upTo) async {
    if (!ref.mounted) return;
    final number = ++_reads;
    var read = Pages<T>(items: const [], pages: 0, hasMore: true);
    while (read.hasMore && read.pages < upTo) {
      final answer = await fetch(read.pages + 1);
      if (!ref.mounted || number != _reads) return;
      switch (answer) {
        case Ok(:final value):
          read = _add(read, value);
        case Err(:final error):
          state = switch (state) {
            ViewData(:final value) => ViewData(
              value,
              staleness: Staleness(fetchedAt: _fetchedAt, failure: error),
            ),
            ViewLoading() || ViewError() => ViewError(error),
          };
          return;
      }
    }
    _fetchedAt = DateTime.now();
    state = ViewData(read);
  }

  /// Reads the next page.
  Future<void> loadMore() async {
    final current = state;
    if (current is! ViewData<Pages<T>> || current.staleness != null) return;
    final before = current.value;
    if (before.loadingMore || !before.hasMore) return;
    final number = ++_reads;
    state = ViewData(before._with(loadingMore: true));
    final answer = await fetch(before.pages + 1);
    if (!ref.mounted || number != _reads) return;
    state = ViewData(switch (answer) {
      Ok(:final value) => _add(before, value),
      Err(:final error) => before._with(moreFailure: error),
    });
  }

  Pages<T> _add(Pages<T> read, ResultPage<T> page) {
    final known = {for (final item in read.items) ?identify(item)};
    final fresh = <T>[];
    for (final item in page.items) {
      final id = identify(item);
      if (id == null || known.add(id)) fresh.add(item);
    }
    return Pages(
      items: List.unmodifiable([...read.items, ...fresh]),
      pages: read.pages + 1,
      // A page with nothing new ends the reading whatever the server says.
      hasMore: page.hasMore && fresh.isNotEmpty,
    );
  }
}

/// What lacks subtitles.
final wantedProvider = NotifierProvider.autoDispose
    .family<WantedController, ViewState<Pages<SubtitleWant>>, ListKey>(
      WantedController.new,
    );

/// Reads the wanted list.
final class WantedController extends PagedController<SubtitleWant> {
  /// For [key].
  WantedController(this.key);

  /// Which list.
  final ListKey key;

  @override
  ServiceResult<ResultPage<SubtitleWant>> fetch(int number) => key.source.guard(
    () => key.source.provider.wanted(key.type, page: number),
  );

  @override
  Object identify(SubtitleWant item) => item.media;
}

/// What the server did, newest first.
final historyProvider = NotifierProvider.autoDispose
    .family<HistoryController, ViewState<Pages<SubtitleHistoryEvent>>, ListKey>(
      HistoryController.new,
    );

/// Reads the history.
final class HistoryController extends PagedController<SubtitleHistoryEvent> {
  /// For [key].
  HistoryController(this.key);

  /// Which list.
  final ListKey key;

  @override
  ServiceResult<ResultPage<SubtitleHistoryEvent>> fetch(int number) => key
      .source
      .guard(() => key.source.provider.history(key.type, page: number));
}

/// The movies or series known to the server.
final titlesProvider = NotifierProvider.autoDispose
    .family<TitlesController, ViewState<Pages<SubtitleTitle>>, ListKey>(
      TitlesController.new,
    );

/// Reads the movies or series.
final class TitlesController extends PagedController<SubtitleTitle> {
  /// For [key].
  TitlesController(this.key);

  /// Which list.
  final ListKey key;

  @override
  ServiceResult<ResultPage<SubtitleTitle>> fetch(int number) =>
      key.source.guard(
        () => switch (key.type) {
          SubtitleMediaType.movie => key.source.provider.browseMovies(
            page: number,
          ),
          SubtitleMediaType.episode => key.source.provider.browseSeries(
            page: number,
          ),
        },
      );

  @override
  Object identify(SubtitleTitle item) => item.media;
}
