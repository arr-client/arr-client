/// The combined history and the combined blocklist of the active profile: what
/// they read and how the pages of several instances make one list.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'server_changes.dart';

/// The history of every instance that has one, read while its tab is open.
final historyFeedProvider =
    NotifierProvider.autoDispose<HistoryFeed, FeedState<HistoryEvent>>(
      HistoryFeed.new,
    );

/// The blocklist of every instance that has one, read while its page is open.
final blocklistFeedProvider =
    NotifierProvider.autoDispose<BlocklistFeed, FeedState<BlocklistEntry>>(
      BlocklistFeed.new,
    );

/// What is known of one instance's list.
final class FeedSource<T> {
  const FeedSource({
    required this.instance,
    this.items,
    this.fetchedAt,
    this.failure,
    this.refreshing = true,
    this.hasMore = false,
    this.loadingMore = false,
    this.moreFailure,
  });

  /// Whose list it is.
  final ActiveInstance instance;

  /// The pages read, newest first; null if no read has succeeded.
  final List<T>? items;

  /// When the first page of [items] was read.
  final DateTime? fetchedAt;

  /// Why reading from the start last failed; null if it succeeded.
  final ServiceFailure? failure;

  /// Whether it is being read from the start.
  final bool refreshing;

  /// Whether the server has older ones.
  final bool hasMore;

  /// Whether the next page is being read.
  final bool loadingMore;

  /// Why the next page could not be read.
  final ServiceFailure? moreFailure;

  String get id => instance.instance.id;

  /// Whether [items] may no longer be what the server has, so that nothing may
  /// be changed on the strength of it.
  bool get isStale => failure != null || refreshing;
}

/// One of an instance's events or entries.
typedef FeedRow<T> = ({FeedSource<T> source, T item});

/// The lists of the instances, and the one list they make.
final class FeedState<T> {
  const FeedState({
    required this.sources,
    required this.rows,
    required this.next,
  });

  /// In the instances' order.
  final List<FeedSource<T>> sources;

  /// Newest first. It stops where an instance has older ones to be read, as
  /// those belong above what the others have from before then.
  final List<FeedRow<T>> rows;

  /// The instances whose next page continues [rows]; empty if none has one.
  final List<FeedSource<T>> next;

  FeedSource<T>? source(String instanceId) =>
      sources.where((source) => source.id == instanceId).firstOrNull;
}

/// Reads each instance on its own, so that one that fails or is slow does not
/// hold up the others, and reads one again after a change to it. Nothing is
/// saved on the device. An instance whose sign-in was rejected is not read until
/// the user has it try again.
abstract class ActivityFeed<T> extends Notifier<FeedState<T>> {
  final _feeds = <String, _Feed<T>>{};
  var _order = <String>[];
  final _retrying = <String>{};

  /// One page of [provider]'s list. Pages start at 1.
  ServiceResult<ResultPage<T>> read(HistoryProvider provider, int page);

  int idOf(T item);

  DateTime dateOf(T item);

  @override
  FeedState<T> build() {
    ref.listen(scopeProvider, (_, scope) {
      _reconcile(scope);
      _publish();
    });
    ref.listen(serverChangesProvider.select((changes) => changes.answered), (
      before,
      answered,
    ) {
      for (final feed in _feeds.values) {
        final client = feed.instance.context.http;
        if (answered[client] != before?[client]) unawaited(_read(feed));
      }
      _publish();
    });
    ref.onDispose(() {
      _feeds.clear();
      _order = [];
    });
    _reconcile(ref.read(appServicesProvider).registry.scope);
    return _snapshot();
  }

  /// Reads from the newest again, for every instance or [instanceId] only. What
  /// is shown stays until it answers.
  Future<void> refresh([String? instanceId]) async {
    _reconcile(ref.read(appServicesProvider).registry.scope);
    final reads = [
      for (final feed in _feeds.values)
        if (instanceId == null || instanceId == feed.id) _read(feed),
    ];
    _publish();
    await Future.wait(reads);
  }

  /// Reads the next page of the instances that continue the list.
  Future<void> loadMore() async {
    await Future.wait([
      for (final source in state.next)
        if (_feeds[source.id] case final feed?) _readMore(feed),
    ]);
  }

  /// Reads [instanceId] again at the user's request: its next page where that
  /// is what failed, otherwise from the start. After a rejected sign-in this
  /// also has it try again, which nothing else here does.
  Future<void> retry(String instanceId, {bool older = false}) async {
    final feed = _feeds[instanceId];
    if (feed == null || !_retrying.add(instanceId)) return;
    final failure = older ? feed.moreFailure : feed.failure;
    final services = ref.read(appServicesProvider);
    try {
      if (feed.instance.instance.authFailed || failure is AuthFailed) {
        await services.profiles.retryAuth(instanceId);
        await services.registry.refresh();
      }
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'A sign-in could not be retried (${error.runtimeType})',
      );
    } finally {
      _retrying.remove(instanceId);
    }
    if (!ref.mounted) return;
    _reconcile(services.registry.scope);
    final now = _feeds[instanceId];
    if (now == null) return;
    // An instance that is now another has been read from the start already.
    if (!identical(now, feed)) return _publish();
    await (older ? _readMore(now) : refresh(instanceId));
  }

  /// Keeps what was read of the instances that are still the same, forgets the
  /// rest and takes up new ones.
  void _reconcile(ProfileScope? scope) {
    final providers = scope?.providers(CapabilityKind.history) ?? const [];
    _order = [for (final (active, _) in providers) active.instance.id];
    _feeds.removeWhere((id, _) => !_order.contains(id));
    for (final (active, _) in providers) {
      final id = active.instance.id;
      final feed = _feeds[id];
      // An edited instance has another client, and starts over.
      if (feed != null &&
          identical(feed.instance.context.http, active.context.http)) {
        feed.instance = active;
        continue;
      }
      final made = _feeds[id] = _Feed<T>(active);
      // Not at once: there may be no state to change yet.
      scheduleMicrotask(() {
        if (ref.mounted && made.generation == 0) unawaited(_read(made));
      });
    }
  }

  bool _isCurrent(_Feed<T> feed, int generation) =>
      ref.mounted &&
      identical(_feeds[feed.id], feed) &&
      generation == feed.generation;

  /// Reads [feed] from the start. An older answer still under way is dropped.
  Future<void> _read(_Feed<T> feed) async {
    final generation = ++feed.generation;
    feed
      ..refreshing = true
      ..loadingMore = false
      ..moreFailure = null;
    // Not published here: a caller may be in the middle of being told something.
    final result = await _page(feed, 1);
    if (result == null || !_isCurrent(feed, generation)) return;
    feed.refreshing = false;
    switch (result) {
      case Ok(:final value):
        feed
          ..items = _newestFirst(value.items)
          ..fetchedAt = DateTime.now()
          ..failure = null
          ..page = 1
          ..hasMore = value.hasMore;
      case Err(:final error):
        feed.failure = error;
    }
    _publish();
  }

  Future<void> _readMore(_Feed<T> feed) async {
    final items = feed.items;
    if (items == null ||
        !feed.hasMore ||
        feed.refreshing ||
        feed.loadingMore ||
        feed.failure != null) {
      return;
    }
    final generation = feed.generation;
    final page = feed.page + 1;
    feed
      ..loadingMore = true
      ..moreFailure = null;
    _publish();
    final result = await _page(feed, page);
    if (result == null || !_isCurrent(feed, generation)) return;
    feed.loadingMore = false;
    switch (result) {
      case Ok(:final value):
        feed
          ..items = _newestFirst([...items, ...value.items])
          ..page = page
          ..hasMore = value.hasMore;
      case Err(:final error):
        feed.moreFailure = error;
    }
    _publish();
  }

  /// One page, or null if there is no answer to show.
  Future<Result<ResultPage<T>, ServiceFailure>?> _page(
    _Feed<T> feed,
    int page,
  ) async {
    // So that the caller has finished before anything is changed.
    await null;
    if (!ref.mounted) return null;
    final active = feed.instance;
    final log = ref.read(appServicesProvider).log;
    if (active.instance.authFailed) return const Err(AuthFailed());
    try {
      final provider = active.capability(CapabilityKind.history);
      if (provider == null) return null;
      final result = await read(provider, page);
      return ref.mounted ? result : null;
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      log.log(LogLevel.error, 'A history read failed (${error.runtimeType})');
      return const Err(MalformedResponse());
    }
  }

  /// Without repeats: what arrives between two reads pushes older ones onto the
  /// next page. The id orders those of the same moment.
  List<T> _newestFirst(List<T> items) => List.unmodifiable(
    {for (final item in items) idOf(item): item}.values.toList()..sort((a, b) {
      final byDate = dateOf(b).compareTo(dateOf(a));
      return byDate != 0 ? byDate : idOf(b).compareTo(idOf(a));
    }),
  );

  void _publish() {
    if (ref.mounted) state = _snapshot();
  }

  FeedState<T> _snapshot() {
    final sources = [
      for (final id in _order)
        if (_feeds[id] case final feed?) feed.snapshot(),
    ];
    final open = [
      for (final source in sources)
        if (source.hasMore &&
            source.failure == null &&
            source.moreFailure == null)
          source,
    ];
    DateTime? oldest(FeedSource<T> source) {
      final items = source.items;
      return items == null || items.isEmpty ? null : dateOf(items.last);
    }

    DateTime? end;
    for (final source in open) {
      final date = oldest(source);
      if (date != null && (end == null || date.isAfter(end))) end = date;
    }
    final rows = <FeedRow<T>>[
      for (final source in sources)
        for (final item in source.items ?? <T>[])
          if (end == null || !dateOf(item).isBefore(end))
            (source: source, item: item),
    ];
    // Stable for those of the same moment: each instance's are in order.
    final order = List.generate(rows.length, (index) => index)
      ..sort((a, b) {
        final byDate = dateOf(rows[b].item).compareTo(dateOf(rows[a].item));
        return byDate != 0 ? byDate : a.compareTo(b);
      });
    return FeedState(
      sources: sources,
      rows: [for (final index in order) rows[index]],
      next: [
        for (final source in open)
          if (oldest(source) == end || oldest(source) == null) source,
      ],
    );
  }
}

final class HistoryFeed extends ActivityFeed<HistoryEvent> {
  @override
  ServiceResult<ResultPage<HistoryEvent>> read(
    HistoryProvider provider,
    int page,
  ) => provider.history(page: page);

  @override
  int idOf(HistoryEvent item) => item.id;

  @override
  DateTime dateOf(HistoryEvent item) => item.date;
}

final class BlocklistFeed extends ActivityFeed<BlocklistEntry> {
  @override
  ServiceResult<ResultPage<BlocklistEntry>> read(
    HistoryProvider provider,
    int page,
  ) => provider.blocklist(page: page);

  @override
  int idOf(BlocklistEntry item) => item.id;

  @override
  DateTime dateOf(BlocklistEntry item) => item.date;
}

final class _Feed<T> {
  _Feed(this.instance);

  ActiveInstance instance;
  List<T>? items;
  DateTime? fetchedAt;
  ServiceFailure? failure;
  var refreshing = true;
  var page = 0;
  var hasMore = false;
  var loadingMore = false;
  ServiceFailure? moreFailure;

  /// Counts the reads from the start.
  var generation = 0;

  String get id => instance.instance.id;

  FeedSource<T> snapshot() => FeedSource(
    instance: instance,
    items: items,
    fetchedAt: fetchedAt,
    failure: failure,
    refreshing: refreshing,
    hasMore: hasMore,
    loadingMore: loadingMore,
    moreFailure: moreFailure,
  );
}
