/// What the combined queue screens read, and the changes they send.
library;

import 'dart:async';
import 'dart:math';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'waiting_release.dart';

/// How long after an answer a queue is asked for again (research R11).
const queuePollInterval = Duration(seconds: 4);

/// The longest pause between reads of a queue that keeps failing.
const queueMaxPollInterval = Duration(seconds: 30);

/// The combined queue of the active profile.
final queueProvider = NotifierProvider<QueueController, QueueState>(
  QueueController.new,
);

/// What is known of the queue of one instance.
final class InstanceQueue {
  const InstanceQueue({
    required this.instance,
    this.items,
    this.fetchedAt,
    this.failure,
    this.outdated = false,
    this.busy = const {},
  });

  /// Whose queue it is.
  final ActiveInstance instance;

  /// The entries as last read; null if no read has succeeded.
  final List<QueueItem>? items;

  /// When [items] was read.
  final DateTime? fetchedAt;

  /// Why the last read failed; null if it succeeded or there was none.
  final ServiceFailure? failure;

  /// Whether reading stopped for a while, so that [items] may be old.
  final bool outdated;

  /// The entries a change is being sent for, or was sent for and has not been
  /// read since.
  final Set<int> busy;

  /// Whether [items] may no longer be what the server has. Nothing may be
  /// changed on the strength of it.
  bool get isStale => failure != null || outdated;

  /// The entry with [id], if [items] has it.
  QueueItem? item(int id) => items?.where((item) => item.id == id).firstOrNull;

  /// Whether a change may be offered for [id].
  bool canChange(int id) => !isStale && !busy.contains(id);

  /// The entries of [items] that what is done to [item] is done to as well,
  /// itself included (see [queueGroup]).
  List<QueueItem> goingWith(QueueItem item) {
    final group = queueGroup(item);
    return [
      for (final other in items ?? const <QueueItem>[])
        if (queueGroup(other) == group) other,
    ];
  }
}

/// The queues of the instances that have one, in the instances' order.
final class QueueState {
  const QueueState(this.queues);

  final List<InstanceQueue> queues;

  InstanceQueue? queue(String instanceId) => queues
      .where((queue) => queue.instance.instance.id == instanceId)
      .firstOrNull;
}

/// Reads the queues while a screen that shows them is visible and the app is in
/// the foreground, and at no other time.
///
/// Each instance is read on its own, so that one that fails or is slow does not
/// hold up the others, and has at most one read under way. An instance whose
/// sign-in was rejected is not read until the user has it try again.
final class QueueController extends Notifier<QueueState> {
  final _feeds = <String, _Feed>{};
  var _order = <String>[];
  final _retrying = <String>{};
  var _watchers = 0;
  var _foreground = true;
  var _polling = false;
  var _disposed = false;

  @override
  QueueState build() {
    _disposed = false;
    _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);
    final lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = _isForeground(state);
        _apply();
      },
    );
    ref.listen(scopeProvider, (_, scope) {
      _reconcile(scope);
      _publish();
    });
    ref.onDispose(() {
      _disposed = true;
      _polling = false;
      lifecycle.dispose();
      for (final feed in _feeds.values) {
        feed.timer?.cancel();
      }
      _feeds.clear();
      _order = [];
    });
    _reconcile(ref.read(appServicesProvider).registry.scope);
    return _snapshot();
  }

  /// Says that a screen showing the queue has become visible. Call the returned
  /// function once it no longer is.
  void Function() watch() {
    _watchers++;
    // Not at once: this is called while widgets are being built.
    scheduleMicrotask(_apply);
    var released = false;
    return () {
      if (released) return;
      released = true;
      _watchers--;
      scheduleMicrotask(_apply);
    };
  }

  /// Reads every queue now, or [instanceId]'s only.
  Future<void> refresh([String? instanceId]) async {
    if (_disposed) return;
    _reconcile(ref.read(appServicesProvider).registry.scope);
    await Future.wait([
      for (final MapEntry(key: id, value: feed) in _feeds.entries)
        if (instanceId == null || instanceId == id) _read(feed..failures = 0),
    ]);
  }

  /// Reads [instanceId]'s queue at the user's request. After a rejected sign-in
  /// this also has it try again, which nothing else here does.
  Future<void> retry(String instanceId) async {
    final feed = _feeds[instanceId];
    if (feed == null ||
        !(feed.instance.instance.authFailed || feed.failure is AuthFailed)) {
      return refresh(instanceId);
    }
    if (!_retrying.add(instanceId)) return;
    final services = ref.read(appServicesProvider);
    final readsBefore = feed.reads;
    try {
      await services.profiles.retryAuth(instanceId);
      await services.registry.refresh();
      if (_disposed) return;
      // This starts the read where the instance is now another or was latched.
      _reconcile(services.registry.scope);
      _publish();
      final now = _feeds[instanceId];
      if (now != null &&
          now.reading == null &&
          now.reads == (identical(now, feed) ? readsBefore : 0)) {
        await _read(now..failures = 0);
      }
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'A sign-in could not be retried (${error.runtimeType})',
      );
    } finally {
      _retrying.remove(instanceId);
    }
  }

  /// Removes [ids] from the queue of [instance]. [affected] is every entry that
  /// goes with them. Sent once.
  ServiceResult<void> remove(
    ActiveInstance instance,
    List<int> ids,
    RemoveOptions options, {
    required Set<int> affected,
  }) => _write(
    instance,
    affected,
    (provider) => switch (ids) {
      [final id] => provider.remove(id, options),
      _ => provider.removeMany(ids, options),
    },
  );

  /// Grabs the delayed entry [id] of [instance] at once. [affected] is every
  /// entry that is grabbed with it. Sent once.
  ServiceResult<void> grabNow(
    ActiveInstance instance,
    int id, {
    required Set<int> affected,
  }) => _write(instance, affected, (provider) => provider.grabNow(id));

  ServiceResult<void> _write(
    ActiveInstance instance,
    Set<int> ids,
    ServiceResult<void> Function(QueueProvider provider) send,
  ) async {
    final provider = instance.capability(CapabilityKind.queue);
    // Nothing is sent for what has been edited, removed or switched away from.
    if (!instance.isCurrent || provider == null) {
      return const Err(Unreachable());
    }
    final log = ref.read(appServicesProvider).log;
    final feed = _feeds[instance.instance.id];
    feed?.writing.addAll(ids);
    _publish();
    try {
      return await send(provider);
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      log.log(LogLevel.error, 'A queue change failed (${error.runtimeType})');
      return const Err(OutcomeUnknown());
    } finally {
      if (feed != null && !_disposed) {
        feed
          ..writing.removeAll(ids)
          ..settling.addAll(ids)
          // A read begun before now may not show the change.
          ..generation += 1
          ..failures = 0;
        _publish();
        if (_polling) unawaited(_read(feed));
      }
    }
  }

  static bool _isForeground(AppLifecycleState? state) => switch (state) {
    // Inactive is still on screen, as beside another app in split screen.
    null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
  };

  /// Starts or stops reading, as the screens and the app now call for.
  void _apply() {
    if (_disposed) return;
    final polling = _watchers > 0 && _foreground;
    if (polling == _polling) return;
    _polling = polling;
    if (polling) {
      _reconcile(ref.read(appServicesProvider).registry.scope);
      for (final feed in _feeds.values) {
        feed.failures = 0;
        unawaited(_read(feed));
      }
    } else {
      for (final feed in _feeds.values) {
        feed.timer?.cancel();
        if (feed.items != null) feed.outdated = true;
      }
    }
    _publish();
  }

  /// Keeps what was read of the instances that are still the same, forgets the
  /// rest and takes up new ones.
  void _reconcile(ProfileScope? scope) {
    final providers = scope?.providers(CapabilityKind.queue) ?? const [];
    _order = [for (final (active, _) in providers) active.instance.id];
    _feeds.removeWhere((id, feed) {
      final gone = !_order.contains(id);
      if (gone) feed.timer?.cancel();
      return gone;
    });
    for (final (active, _) in providers) {
      final id = active.instance.id;
      var feed = _feeds[id];
      // An edited instance has another client, and starts over.
      if (feed != null &&
          !identical(feed.instance.context.http, active.context.http)) {
        feed.timer?.cancel();
        feed = null;
      }
      if (feed == null) {
        feed = _feeds[id] = _Feed(active);
        if (_polling) unawaited(_read(feed));
        continue;
      }
      final wasLatched = feed.instance.instance.authFailed;
      feed.instance = active;
      if (wasLatched && !active.instance.authFailed) {
        feed
          ..failure = null
          ..failures = 0;
        if (_polling) unawaited(_read(feed));
      }
    }
  }

  /// Reads the queue of [feed], or joins the read under way.
  Future<void> _read(_Feed feed) =>
      feed.reading ??= _readNow(feed).whenComplete(() => feed.reading = null);

  Future<void> _readNow(_Feed feed) async {
    // So that [_Feed.reading] is set before anything can finish.
    await null;
    while (!_disposed && identical(_feeds[feed.id], feed)) {
      feed.timer?.cancel();
      if (feed.instance.instance.authFailed) {
        feed.failure = const AuthFailed();
        _publish();
        return;
      }
      final scope = ref.read(appServicesProvider).registry.scope;
      if (scope == null) return;
      final generation = feed.generation;
      feed.reads += 1;
      Result<List<QueueItem>, ServiceFailure>? result;
      await for (final answer in scope.aggregate(
        CapabilityKind.queue,
        (provider) => provider.queue(),
        where: (instance, _) => instance.instance.id == feed.id,
      )) {
        result = answer.parts.firstOrNull?.result;
      }
      if (_disposed || !identical(_feeds[feed.id], feed)) return;
      // No longer current; the change of scope takes care of it.
      if (result == null) return;
      // A change was sent meanwhile: this answer may be from before it.
      if (generation != feed.generation) continue;
      switch (result) {
        case Ok(:final value):
          feed
            ..items = List.unmodifiable(value)
            ..fetchedAt = DateTime.now()
            ..failure = null
            ..failures = 0
            // Reading may have stopped while this was under way.
            ..outdated = !_polling && feed.outdated;
        case Err(:final error):
          feed
            ..failure = error
            ..failures += 1;
      }
      feed.settling.clear();
      _publish();
      if (_polling) {
        final pause = queuePollInterval * pow(2, min(feed.failures, 3)).toInt();
        feed.timer = Timer(
          pause > queueMaxPollInterval ? queueMaxPollInterval : pause,
          () => unawaited(_read(feed)),
        );
      }
      return;
    }
  }

  void _publish() {
    if (!_disposed) state = _snapshot();
  }

  QueueState _snapshot() => QueueState([
    for (final id in _order)
      if (_feeds[id] case final feed?) feed.snapshot(),
  ]);
}

final class _Feed {
  _Feed(this.instance);

  ActiveInstance instance;
  List<QueueItem>? items;
  DateTime? fetchedAt;
  ServiceFailure? failure;
  var outdated = false;

  /// Failed reads in a row.
  var failures = 0;

  /// Counts the reads sent.
  var reads = 0;

  /// Counts the changes sent.
  var generation = 0;

  final writing = <int>{};
  final settling = <int>{};
  Timer? timer;
  Future<void>? reading;

  String get id => instance.instance.id;

  InstanceQueue snapshot() => InstanceQueue(
    instance: instance,
    items: items,
    fetchedAt: fetchedAt,
    failure: failure,
    outdated: outdated,
    busy: {...writing, ...settling},
  );
}
