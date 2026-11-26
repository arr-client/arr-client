/// What the history of one item reads.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'server_changes.dart';

/// One item, and the client of its instance. An edited instance has another
/// client, so that what was read through the old one is not shown for it.
typedef ItemHistoryKey = ({ItemRef item, Object client});

/// The history of one item, read while its screen is open.
final itemHistoryProvider = NotifierProvider.autoDispose
    .family<ItemHistoryController, ItemHistoryState, ItemHistoryKey>(
      ItemHistoryController.new,
    );

/// What is known of the history of one item.
final class ItemHistoryState {
  const ItemHistoryState({
    this.events,
    this.fetchedAt,
    this.failure,
    this.refreshing = true,
    this.page = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.moreFailure,
  });

  /// The events of the pages read, newest first; null if no read has succeeded.
  final List<HistoryEvent>? events;

  /// When the first page of [events] was read.
  final DateTime? fetchedAt;

  /// Why reading from the start last failed; null if it succeeded.
  final ServiceFailure? failure;

  /// Whether it is being read from the start.
  final bool refreshing;

  /// The last page read.
  final int page;

  /// Whether the server has older events.
  final bool hasMore;

  /// Whether the next page is being read.
  final bool loadingMore;

  /// Why the next page could not be read.
  final ServiceFailure? moreFailure;

  /// The same events, with how reading stands now.
  ItemHistoryState _reading({
    bool refreshing = false,
    bool loadingMore = false,
    ServiceFailure? failure,
    ServiceFailure? moreFailure,
  }) => ItemHistoryState(
    events: events,
    fetchedAt: fetchedAt,
    page: page,
    hasMore: hasMore,
    refreshing: refreshing,
    loadingMore: loadingMore,
    failure: failure,
    moreFailure: moreFailure,
  );
}

/// Reads the pages of an item's history as they are asked for. Nothing of it is
/// saved on the device.
final class ItemHistoryController extends Notifier<ItemHistoryState> {
  ItemHistoryController(this.key);

  final ItemHistoryKey key;

  /// Counts the reads from the start, so that an older answer is dropped.
  var _generation = 0;
  var _retrying = false;

  @override
  ItemHistoryState build() {
    // A change may have altered the history, whatever the server answered.
    ref.listen(
      serverChangesProvider.select((changes) => changes.answered[key.client]),
      (_, _) => unawaited(refresh()),
    );
    // Not at once: there is no state to change until this returns.
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(refresh());
    });
    return const ItemHistoryState();
  }

  /// Reads from the newest event again. What is shown stays until it answers.
  Future<void> refresh() async {
    final generation = ++_generation;
    state = state._reading(refreshing: true, failure: state.failure);
    final result = await _read(1);
    if (result == null || generation != _generation) return;
    state = switch (result) {
      Ok(:final value) => ItemHistoryState(
        events: _newestFirst(value.items),
        fetchedAt: DateTime.now(),
        refreshing: false,
        page: 1,
        hasMore: value.hasMore,
      ),
      Err(:final error) => state._reading(failure: error),
    };
  }

  /// Reads the next page, if there is one and nothing else is being read.
  Future<void> loadMore() async {
    final events = state.events;
    if (events == null ||
        !state.hasMore ||
        state.refreshing ||
        state.loadingMore ||
        state.failure != null) {
      return;
    }
    final generation = _generation;
    final page = state.page + 1;
    state = state._reading(loadingMore: true);
    final result = await _read(page);
    if (result == null || generation != _generation) return;
    state = switch (result) {
      Ok(:final value) => ItemHistoryState(
        events: _newestFirst([...events, ...value.items]),
        fetchedAt: state.fetchedAt,
        refreshing: false,
        page: page,
        hasMore: value.hasMore,
      ),
      Err(:final error) => state._reading(moreFailure: error),
    };
  }

  /// Reads again at the user's request: the next page where that is what
  /// failed, otherwise from the start. After a rejected sign-in this also has
  /// the instance try again, which nothing else here does.
  Future<void> retry({bool older = false}) async {
    if (_retrying) return;
    _retrying = true;
    final failure = older ? state.moreFailure : state.failure;
    final services = ref.read(appServicesProvider);
    try {
      final active = _active();
      if (active != null &&
          (active.instance.authFailed || failure is AuthFailed)) {
        await services.profiles.retryAuth(key.item.instanceId);
        await services.registry.refresh();
      }
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'A sign-in could not be retried (${error.runtimeType})',
      );
    } finally {
      _retrying = false;
    }
    if (!ref.mounted) return;
    await (older ? loadMore() : refresh());
  }

  /// The instance, while it is still the one this was made for.
  ActiveInstance? _active() {
    final active = ref
        .read(appServicesProvider)
        .registry
        .scope
        ?.instance(key.item.instanceId);
    return active != null && identical(active.context.http, key.client)
        ? active
        : null;
  }

  /// One page, or null if there is no answer to show.
  Future<Result<ResultPage<HistoryEvent>, ServiceFailure>?> _read(
    int page,
  ) async {
    final active = _active();
    final provider = active?.capability(CapabilityKind.history);
    if (active == null || provider == null) return null;
    final log = ref.read(appServicesProvider).log;
    Result<ResultPage<HistoryEvent>, ServiceFailure> result;
    if (active.instance.authFailed) {
      result = const Err(AuthFailed());
    } else {
      try {
        result = await provider.history(
          target: MediaTarget(key.item),
          page: page,
        );
      } catch (error) {
        // The type only: the text of an error may quote an address or a secret.
        log.log(LogLevel.error, 'A history read failed (${error.runtimeType})');
        result = const Err(MalformedResponse());
      }
    }
    return ref.mounted && _active() != null ? result : null;
  }

  /// Without repeats: events that arrive between two reads push older ones onto
  /// the next page. The id orders events of the same moment.
  static List<HistoryEvent> _newestFirst(List<HistoryEvent> events) =>
      List.unmodifiable(
        {for (final event in events) event.id: event}.values.toList()
          ..sort((a, b) {
            final byDate = b.date.compareTo(a.date);
            return byDate != 0 ? byDate : b.id.compareTo(a.id);
          }),
      );
}
