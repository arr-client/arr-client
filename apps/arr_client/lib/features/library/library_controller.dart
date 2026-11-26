import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/composition.dart';
import '../../app/providers.dart';
import 'library_entry.dart';
import 'library_query.dart';
import 'library_source.dart';
import 'library_state.dart';

/// The library of one kind, such as the movies, of the active profile.
///
/// It stays for as long as the app does, so that coming back to the tab shows
/// what was there. [LibraryController.refresh] asks the servers again.
final libraryProvider =
    NotifierProvider.family<LibraryController, LibraryState, MediaKind>(
      LibraryController.new,
    );

/// Shows what is cached first, then what each instance answers, one instance
/// not waiting for another, and keeps the view the user chose. An item found to
/// be gone from its server, on whatever screen, leaves the list at once.
class LibraryController extends Notifier<LibraryState> {
  LibraryController(this.kind);

  /// The kind of the top-level items.
  final MediaKind kind;

  /// How old an answer may be before coming back to the library asks again.
  static const maxAge = Duration(minutes: 5);

  /// The clock that ages are measured with.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  late AppServices _services;
  String? _profileId;
  LibraryView? _view;

  /// By instance id, in the profile's order.
  var _sources = <String, _Instance>{};

  // What was last worked out, and what it was worked out from.
  List<Object?> _sortedFrom = const [];
  List<LibraryEntry> _sorted = const [];
  List<Object?> _filteredFrom = const [];
  List<LibraryEntry> _filtered = const [];

  @override
  LibraryState build() {
    _services = ref.watch(appServicesProvider);
    _profileId = null;
    _view = null;
    _sources = {};
    _sortedFrom = const [];
    _filteredFrom = const [];
    ref.listen(scopeProvider, (_, scope) => _apply(scope));
    final removals = _services.cache.removals.listen(_remove);
    ref.onDispose(removals.cancel);
    // Not during build, which must not set the state.
    scheduleMicrotask(() {
      if (ref.mounted) _apply(ref.read(scopeProvider));
    });
    return const LibraryState();
  }

  /// Asks every instance again. Completes when all have answered.
  Future<void> refresh() => Future.wait([
    for (final instance in _sources.values.toList()) _load(instance),
  ]);

  /// Asks again those that answered, or failed to, [maxAge] ago or longer, so
  /// that old states are not taken for current ones.
  Future<void> refreshIfOld() => Future.wait([
    for (final instance in _sources.values.toList())
      if (instance.answeredAt case final at?
          when now().difference(at) >= maxAge)
        _load(instance),
  ]);

  /// Asks one instance again.
  Future<void> retry(String instanceId) async {
    // Also finds out whether it can be reached again.
    _services.prober.probe(instanceId);
    final instance = _sources[instanceId];
    if (instance != null) await _load(instance);
  }

  /// Asks one instance again after a change to it. A read under way may have
  /// been answered before the change, so another follows it.
  Future<void> reload(String instanceId) async {
    final instance = _sources[instanceId];
    if (instance == null) return;
    await instance.loading;
    if (ref.mounted && identical(_sources[instanceId], instance)) {
      await _load(instance);
    }
  }

  /// Shows [view] and remembers it for the profile.
  void setView(LibraryView view) {
    if (view == _view) return;
    _view = view;
    _publish();
    unawaited(_save(view));
  }

  void setFilters(LibraryFilters filters) {
    final view = _view;
    if (view == null) return;
    setView(
      LibraryView(
        layout: view.layout,
        sort: view.sort,
        filters: filters,
        instanceScope: view.instanceScope,
      ),
    );
  }

  void setText(String text) {
    final filters = _view?.filters;
    if (filters == null) return;
    setFilters(
      LibraryFilters(
        text: text,
        states: filters.states,
        monitored: filters.monitored,
        qualityProfiles: filters.qualityProfiles,
        tags: filters.tags,
      ),
    );
  }

  /// Removes every filter, the text included. The scope stays.
  void clearFilters() => setFilters(const LibraryFilters());

  void setSort(LibrarySort sort) {
    final view = _view;
    if (view == null) return;
    setView(
      LibraryView(
        layout: view.layout,
        sort: sort,
        filters: view.filters,
        instanceScope: view.instanceScope,
      ),
    );
  }

  void setLayout(LibraryLayout layout) {
    final view = _view;
    if (view == null) return;
    setView(
      LibraryView(
        layout: layout,
        sort: view.sort,
        filters: view.filters,
        instanceScope: view.instanceScope,
      ),
    );
  }

  /// Narrows the view to one instance, or with null shows all.
  void setScope(String? instanceId) {
    final view = _view;
    if (view == null) return;
    setView(
      LibraryView(
        layout: view.layout,
        sort: view.sort,
        filters: view.filters,
        instanceScope: instanceId,
      ),
    );
  }

  void _apply(ProfileScope? scope) {
    if (scope == null) {
      _profileId = null;
      _view = null;
      _sources = {};
      _publish();
      return;
    }
    if (scope.profileId != _profileId) {
      _profileId = scope.profileId;
      _view = null;
      _sources = {};
      unawaited(_readView(scope.profileId));
    }

    final sources = <String, _Instance>{};
    final toLoad = <_Instance>[];
    for (final (active, provider) in scope.providers(CapabilityKind.library)) {
      if (provider.itemKind != kind) continue;
      final id = active.instance.id;
      var instance = _sources[id];
      // An edited instance has another client: what it was is not shown.
      if (instance == null ||
          !identical(
            instance.source.active.context.http,
            active.context.http,
          )) {
        instance = _Instance(provider, LibrarySource(active: active));
        toLoad.add(instance);
      } else {
        final before = instance.source.active.connection;
        instance.source = instance.source.copyWith(active: active);
        // Reachable again after a failed load.
        if (active.connection is ConnectionOnline &&
            before is! ConnectionOnline &&
            instance.source.failure != null) {
          toLoad.add(instance);
        }
      }
      sources[id] = instance;
    }
    _sources = sources;
    _publish();
    for (final instance in toLoad) {
      unawaited(_load(instance));
    }
  }

  Future<void> _readView(String profileId) async {
    var view = const LibraryView();
    try {
      view = await _services.preferences.view(profileId, kind);
    } catch (error) {
      _warn('A library view could not be read', error);
    }
    if (!ref.mounted || _profileId != profileId) return;
    _view = view;
    _publish();
    _dropUnresolved();
  }

  Future<void> _save(LibraryView view) async {
    final profileId = _profileId;
    if (profileId == null) return;
    try {
      await _services.preferences.saveView(profileId, kind, view);
    } catch (error) {
      _warn('A library view could not be saved', error);
    }
  }

  Future<void> _load(_Instance instance) =>
      instance.loading ??= _fetch(instance).whenComplete(() {
        instance.loading = null;
      });

  void _remove(ItemRef gone) {
    final instance = _sources[gone.instanceId];
    if (instance == null || gone.kind != kind) return;
    // A list asked for before may still hold it.
    instance.removed.add(gone);
    final entries = instance.source.entries;
    if (entries == null || !entries.any((entry) => entry.item.ref == gone)) {
      return;
    }
    _update(
      instance,
      instance.source.copyWith(
        entries: [
          for (final entry in entries)
            if (entry.item.ref != gone) entry,
        ],
      ),
    );
  }

  Future<void> _fetch(_Instance instance) async {
    final provider = instance.provider;
    instance.removed.clear();
    _update(instance, instance.source.copyWith(isLoading: true));
    if (instance.source.options == null) {
      final saved = await _read(provider.cachedOptions);
      if (!_isCurrent(instance)) return;
      if (saved case Ok(value: final saved?)) {
        _update(instance, instance.source.copyWith(options: saved.value));
      }
    }
    if (instance.source.entries == null) {
      final cached = await _read(provider.cachedList);
      if (!_isCurrent(instance)) return;
      // A cache that cannot be read is as one that is empty: the server is
      // asked next and says what is wrong.
      if (cached case Ok(value: final cached?)) {
        _update(
          instance,
          instance.source.copyWith(
            entries: _entries(cached.value),
            fetchedAt: () => cached.fetchedAt,
          ),
        );
      }
    }
    final options = _fetchOptions(instance);
    final result = await _read(provider.list);
    if (_isCurrent(instance)) {
      _update(instance, switch (result) {
        Ok(:final value) => instance.source.copyWith(
          entries: _entries([
            for (final item in value)
              if (!instance.removed.contains(item.ref)) item,
          ]),
          fetchedAt: () => null,
          failure: () => null,
          isLoading: false,
        ),
        // What was there stays, now as saved data.
        Err(:final error) => instance.source.copyWith(
          fetchedAt: () =>
              instance.source.fetchedAt ??
              (instance.source.entries == null ? null : instance.loadedAt),
          failure: () => error,
          isLoading: false,
        ),
      });
      instance.answeredAt = now();
      if (result is Ok) instance.loadedAt = instance.answeredAt;
    }
    await options;
  }

  Future<void> _fetchOptions(_Instance instance) async {
    final result = await _read(instance.provider.options);
    if (!_isCurrent(instance)) return;
    switch (result) {
      case Ok(:final value):
        instance.optionsAnswered = true;
        _update(
          instance,
          instance.source.copyWith(options: value, optionsFailed: false),
        );
        _dropUnresolved();
      case Err():
        _update(instance, instance.source.copyWith(optionsFailed: true));
    }
  }

  /// Drops the saved filter ids that the servers no longer have. Saved options
  /// do not say what a server has now.
  void _dropUnresolved() {
    final filters = _view?.filters;
    if (filters == null) return;
    final resolved = filters.withoutUnresolved({
      for (final MapEntry(key: id, value: instance) in _sources.entries)
        if (instance.optionsAnswered) id: ?instance.source.options,
    });
    if (resolved != filters) setFilters(resolved);
  }

  /// What [read] returns; a module that throws has answered what cannot be
  /// understood, so that it does not hold up the others.
  Future<Result<T, ServiceFailure>> _read<T>(
    ServiceResult<T> Function() read,
  ) async {
    try {
      return await read();
    } catch (error) {
      _services.log.log(
        LogLevel.error,
        'A module failed to read (${error.runtimeType})',
      );
      return const Err(MalformedResponse());
    }
  }

  /// Whether what [instance] answers is still to be shown.
  bool _isCurrent(_Instance instance) =>
      ref.mounted &&
      instance.source.active.isCurrent &&
      identical(_sources[instance.source.id], instance);

  void _update(_Instance instance, LibrarySource source) {
    instance.source = source;
    _publish();
  }

  static List<LibraryEntry> _entries(List<LibraryItem> items) => [
    for (final item in items) LibraryEntry(item),
  ];

  void _publish() {
    final view = _view;
    final all = LibraryState(
      profileId: _profileId,
      view: view,
      sources: [for (final instance in _sources.values) instance.source],
    );
    final shown = all.shown;

    // Sorting and filtering thousands of items is done only when what they
    // depend on has changed, not for a connection or an option.
    final sort = view?.sort ?? const LibrarySort();
    final sortedFrom = [sort, for (final source in shown) source.entries];
    if (!_same(sortedFrom, _sortedFrom)) {
      _sortedFrom = sortedFrom;
      _sorted = sortEntries([
        for (final source in shown) ...?source.entries,
      ], sort);
    }
    final filters = view?.filters ?? const LibraryFilters();
    final ids = {for (final source in shown) source.id};
    final filteredFrom = [_sorted, filters, ...ids];
    if (!_same(filteredFrom, _filteredFrom)) {
      _filteredFrom = filteredFrom;
      _filtered = filterEntries(_sorted, filters, ids);
    }

    state = LibraryState(
      profileId: _profileId,
      view: view,
      sources: all.sources,
      visible: _filtered,
      total: _sorted.length,
    );
  }

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      // Lists compare by identity, which is what is wanted here.
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // The type only: the text of an error may quote an address or a secret.
  void _warn(String message, Object error) =>
      _services.log.log(LogLevel.warning, '$message (${error.runtimeType})');
}

/// One instance's part, and what is under way for it.
final class _Instance {
  _Instance(this.provider, this.source);

  final LibraryProvider provider;
  LibrarySource source;
  Future<void>? loading;

  /// When the server last supplied the items, in this run.
  DateTime? loadedAt;

  /// When the last read of the items ended, well or not.
  DateTime? answeredAt;

  /// Whether the server has supplied the options, in this run.
  var optionsAnswered = false;

  /// The items found to be gone since the last read of the items began.
  final removed = <ItemRef>{};
}
