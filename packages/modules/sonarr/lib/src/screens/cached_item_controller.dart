import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

/// State read from the server that is also cached: what was saved is shown with
/// its age first, and stays, with the reason, if the server cannot be read.
abstract class CachedItemController<T> extends Notifier<ViewState<T>> {
  /// What was last fetched, without a network request.
  ServiceResult<Cached<T>?> readCached();

  /// From the server.
  ServiceResult<T> fetch();

  /// The items found to be gone from the server, by this screen or another.
  Stream<ItemRef> get removals;

  /// What is left of [shown] now that [gone] is; null if it is unaffected.
  ViewState<T>? without(ViewState<T> shown, ItemRef gone);

  DateTime _fetchedAt = DateTime.now();
  Future<void>? _loading;

  // Counts the loads, so that only the newest one is believed.
  int _load = 0;

  @override
  ViewState<T> build() {
    final subscription = removals.listen((gone) {
      if (without(state, gone) case final next?) state = next;
    });
    ref.onDispose(subscription.cancel);
    unawaited(_start(_first));
    return const ViewLoading();
  }

  /// Fetches again. A fetch already under way is not repeated.
  Future<void> refresh() => _loading ?? reload();

  /// Fetches again even if a fetch is under way, whose answer is then dropped:
  /// it may be older than a change just made.
  Future<void> reload() =>
      // A flow or a change may end after the screen was left.
      ref.mounted ? _start(_again) : Future.value();

  Future<void> _start(Future<void> Function(int load) run) {
    final load = ++_load;
    return _loading = run(load).whenComplete(() {
      if (load == _load) _loading = null;
    });
  }

  Future<void> _first(int load) async {
    final cached = await readCached();
    if (!ref.mounted || load != _load) return;
    // A cache that cannot be read is as good as an empty one.
    if (cached case Ok(value: final saved?)) {
      _fetchedAt = saved.fetchedAt;
      state = ViewData(
        saved.value,
        staleness: Staleness(fetchedAt: _fetchedAt),
      );
    }
    await _fetch(load);
  }

  Future<void> _again(int load) async {
    switch (state) {
      // The old failure goes while the server is asked again.
      case ViewData(:final value, staleness: Staleness()):
        state = ViewData(value, staleness: Staleness(fetchedAt: _fetchedAt));
      case ViewError():
        state = const ViewLoading();
      case ViewData() || ViewLoading():
        break;
    }
    await _fetch(load);
  }

  Future<void> _fetch(int load) async {
    final result = await fetch();
    if (!ref.mounted || load != _load) return;
    switch (result) {
      case Ok(:final value):
        _fetchedAt = DateTime.now();
        state = ViewData(value);
      // Gone from the server: what was saved no longer stands for anything.
      case Err(error: NotFound()):
        state = const ViewError(NotFound());
      case Err(:final error):
        state = switch (state) {
          ViewData(:final value) => ViewData(
            value,
            staleness: Staleness(fetchedAt: _fetchedAt, failure: error),
          ),
          ViewLoading() || ViewError() => ViewError(error),
        };
    }
  }
}
