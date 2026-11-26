/// What the wanted lists read from the active profile's services.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// The two wanted lists, in the order of their tabs.
enum WantedKind { missing, cutoffUnmet }

/// The pages read of one list: their items, each once and in the server's
/// order, how many pages that was and whether the server has more.
typedef WantedPages = ({List<LibraryItem> items, int pages, bool hasMore});

const WantedPages _nothingRead = (items: [], pages: 0, hasMore: true);

/// Whether [item], or what it belongs to, is among [gone].
bool isGone(LibraryItem item, Set<ItemRef> gone) =>
    gone.contains(item.ref) || gone.contains(item.parent);

/// Reads the pages after [from], up to page [upTo] or, without it, to the end
/// of the list. [onPage] is told how many items there are so far.
///
/// Null once [proceed] says that the answer is no longer wanted.
Future<Result<WantedPages, ServiceFailure>?> readWantedPages(
  WantedProvider provider,
  WantedKind kind, {
  required Logger log,
  required bool Function() proceed,
  WantedPages from = _nothingRead,
  int? upTo,
  void Function(int found)? onPage,
}) async {
  // By ref: the list can change between pages, which then repeat items.
  final items = {for (final item in from.items) item.ref: item};
  var pages = from.pages;
  var hasMore = from.hasMore;
  while (hasMore && (upTo == null || pages < upTo)) {
    if (!proceed()) return null;
    Result<ResultPage<LibraryItem>, ServiceFailure> result;
    try {
      result = await switch (kind) {
        WantedKind.missing => provider.missing(page: pages + 1),
        WantedKind.cutoffUnmet => provider.cutoffUnmet(page: pages + 1),
      };
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      log.log(LogLevel.error, 'A wanted list failed (${error.runtimeType})');
      result = const Err(MalformedResponse());
    }
    if (!proceed()) return null;
    switch (result) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final before = items.length;
        for (final item in value.items) {
          items.putIfAbsent(item.ref, () => item);
        }
        pages++;
        // A page with nothing new ends the reading whatever the server says,
        // so that one repeating a page cannot keep it going.
        hasMore = value.hasMore && items.length > before;
        onPage?.call(items.length);
    }
  }
  return Ok((
    items: List.unmodifiable(items.values),
    pages: pages,
    hasMore: hasMore,
  ));
}

/// What one service has given of one list.
final class WantedList {
  const WantedList({
    required this.instanceId,
    required this.name,
    this.loading = true,
    this.read,
    this.fetchedAt,
    this.failure,
  });

  final String instanceId;

  /// The instance's name.
  final String name;

  /// Whether a read is under way.
  final bool loading;

  /// What it last gave; null if it never answered.
  final WantedPages? read;

  /// When [read] was last read.
  final DateTime? fetchedAt;

  /// Why the last read failed.
  final ServiceFailure? failure;
}

/// One list of every service that has wanted lists, in the instances' order;
/// null while switching profile.
final wantedProvider = NotifierProvider.autoDispose
    .family<WantedController, List<WantedList>?, WantedKind>(
      WantedController.new,
    );

/// Reads each service on its own, so that one that fails or is slow does not
/// hold up the others. A list is read a page at a time, as the user asks for
/// more. What was read stays while it is read again, also if that fails, and
/// it is read again when the app resumes and when the user asks. An item found
/// to be gone from its server, on whatever screen, leaves the list at once.
class WantedController extends Notifier<List<WantedList>?> {
  WantedController(this.kind);

  final WantedKind kind;

  var _lists = <WantedList>[];

  /// The latest read of each instance, so that an older one cannot overtake it.
  final _latest = <String, int>{};
  var _reads = 0;

  /// The items of each instance found to be gone since its list was last read
  /// from the start or further.
  final _removed = <String, Set<ItemRef>>{};

  @override
  List<WantedList>? build() {
    // Only which instances there are, and as what: the scope is also replaced
    // when no more than a connection changes.
    ref.watch(scopeProvider.select(_servicesKey));
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(reload()));
    final removals = ref
        .read(appServicesProvider)
        .cache
        .removals
        .listen(_remove);
    ref.onDispose(() {
      lifecycle.dispose();
      unawaited(removals.cancel());
      _latest.clear();
    });

    final scope = ref.read(scopeProvider);
    if (scope == null) return null;
    _lists = [
      for (final (active, _) in scope.providers(CapabilityKind.wanted))
        WantedList(instanceId: active.instance.id, name: active.instance.name),
    ];
    for (final list in _lists) {
      unawaited(_load(list.instanceId));
    }
    return List.unmodifiable(_lists);
  }

  /// Reads again the pages already read, of every service or of [instanceId].
  Future<void> reload([String? instanceId]) async {
    await Future.wait([
      for (final list in _lists)
        if (instanceId == null || list.instanceId == instanceId)
          _load(list.instanceId),
    ]);
  }

  /// Reads the next page of [instanceId].
  Future<void> loadMore(String instanceId) async {
    final list = _list(instanceId);
    if (list == null || list.loading || !(list.read?.hasMore ?? false)) return;
    await _load(instanceId, more: true);
  }

  /// Reads [instanceId] again at the user's request. After a rejected sign-in
  /// this also has it try again, which nothing else here does.
  Future<void> retry(String instanceId) async {
    final services = ref.read(appServicesProvider);
    final active = services.registry.scope?.instance(instanceId);
    if (active != null &&
        (active.instance.authFailed ||
            _list(instanceId)?.failure is AuthFailed)) {
      try {
        await services.profiles.retryAuth(instanceId);
        await services.registry.refresh();
      } catch (error) {
        services.log.log(
          LogLevel.warning,
          'A sign-in could not be retried (${error.runtimeType})',
        );
      }
    }
    if (ref.mounted) await reload(instanceId);
  }

  WantedList? _list(String instanceId) =>
      _lists.where((list) => list.instanceId == instanceId).firstOrNull;

  void _put(WantedList next) {
    _lists = [
      for (final list in _lists)
        list.instanceId == next.instanceId ? next : list,
    ];
    state = List.unmodifiable(_lists);
  }

  void _remove(ItemRef gone) {
    // A list asked for before may still hold it.
    (_removed[gone.instanceId] ??= {}).add(gone);
    final list = _list(gone.instanceId);
    final read = list?.read;
    if (list == null || read == null) return;
    final kept = _without(read, {gone});
    if (kept.items.length == read.items.length) return;
    _put(
      WantedList(
        instanceId: list.instanceId,
        name: list.name,
        loading: list.loading,
        read: kept,
        fetchedAt: list.fetchedAt,
        failure: list.failure,
      ),
    );
  }

  static WantedPages _without(WantedPages read, Set<ItemRef> gone) => (
    items: List.unmodifiable([
      for (final item in read.items)
        if (!isGone(item, gone)) item,
    ]),
    pages: read.pages,
    hasMore: read.hasMore,
  );

  Future<void> _load(String instanceId, {bool more = false}) async {
    final number = _latest[instanceId] = ++_reads;
    // There is no state to change until `build` has returned.
    await null;
    bool wanted() => ref.mounted && _latest[instanceId] == number;
    if (!wanted()) return;
    final services = ref.read(appServicesProvider);
    final active = services.registry.scope?.instance(instanceId);
    final provider = active?.capability(CapabilityKind.wanted);
    final before = _list(instanceId);
    if (active == null || provider == null || before == null) return;
    _removed.remove(instanceId);
    _put(
      WantedList(
        instanceId: instanceId,
        name: before.name,
        read: before.read,
        fetchedAt: before.fetchedAt,
        failure: before.failure,
      ),
    );
    final loaded = before.read?.pages ?? 0;
    final result = active.instance.authFailed
        ? const Err<WantedPages, ServiceFailure>(AuthFailed())
        : await readWantedPages(
            provider,
            kind,
            log: services.log,
            proceed: () => wanted() && active.isCurrent,
            from: more ? before.read! : _nothingRead,
            upTo: more ? loaded + 1 : max(1, loaded),
          );
    // An edited instance is read anew by `build`.
    // As it is now: items may have left it while this was under way.
    final now = _list(instanceId);
    if (result == null || !wanted() || now == null) return;
    final gone = _removed[instanceId] ?? const {};
    _put(switch (result) {
      Ok(:final value) => WantedList(
        instanceId: instanceId,
        name: now.name,
        loading: false,
        read: _without(value, gone),
        fetchedAt: DateTime.now(),
      ),
      Err(:final error) => WantedList(
        instanceId: instanceId,
        name: now.name,
        loading: false,
        read: now.read,
        fetchedAt: now.fetchedAt,
        failure: error,
      ),
    });
  }

  static String? _servicesKey(ProfileScope? scope) => scope == null
      ? null
      : jsonEncode([
          scope.profileId,
          for (final active in scope.instances)
            if (active.capabilities.contains(CapabilityKind.wanted))
              [
                active.instance.id,
                active.instance.name,
                // Another one after an edit.
                identityHashCode(active.context.http),
              ],
        ]);
}
