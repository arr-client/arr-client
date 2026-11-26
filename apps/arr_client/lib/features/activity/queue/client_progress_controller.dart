/// The download clients' own figures for what is queued (spec story 7). They
/// are only ever read (FR-031).
library;

import 'dart:async';
import 'dart:math';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'queue_controller.dart' show queueMaxPollInterval, queuePollInterval;

/// The figures of the active profile's download clients.
final clientProgressProvider =
    NotifierProvider<ClientProgressController, ClientProgressState>(
      ClientProgressController.new,
    );

/// What is known of one download client instance.
final class ClientProgress {
  const ClientProgress({required this.instance, this.torrents, this.failure});

  /// Which client it is.
  final ActiveInstance instance;

  /// Its torrents as just read; null if there is no current answer, so that old
  /// figures are never shown as live ones.
  final List<DownloadProgress>? torrents;

  /// Why the last read failed; null if it succeeded or there was none.
  final ServiceFailure? failure;
}

/// The download clients, in the instances' order.
final class ClientProgressState {
  const ClientProgressState(this.clients);

  final List<ClientProgress> clients;

  /// The figures for [item], from the first client that has its download.
  DownloadProgress? match(QueueItem item) => matchProgress(
    item,
    clients.expand((client) => client.torrents ?? const []),
  );

  /// What to call the client of [instanceId]: its product, and the instance's
  /// name where there are several.
  String nameOf(String instanceId) {
    final client = clients
        .firstWhere((client) => client.instance.instance.id == instanceId)
        .instance;
    final product = client.module.descriptor.displayName;
    return clients.length > 1 ? '$product (${client.instance.name})' : product;
  }
}

/// Reads the download clients while a screen that shows their figures is
/// visible and the app is in the foreground, and at no other time.
///
/// Each instance has at most one read under way. After a rejected sign-in an
/// instance is not read again until the user has it try again: another attempt
/// can get the address banned.
final class ClientProgressController extends Notifier<ClientProgressState> {
  final _feeds = <String, _Feed>{};
  var _order = <String>[];
  final _retrying = <String>{};
  var _watchers = 0;
  var _foreground = true;
  var _polling = false;
  var _disposed = false;

  @override
  ClientProgressState build() {
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

  /// Says that a screen showing the figures has become visible. Call the
  /// returned function once it no longer is.
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

  /// Reads every client now, except those whose sign-in was rejected.
  Future<void> refresh() async {
    if (_disposed) return;
    _reconcile(ref.read(appServicesProvider).registry.scope);
    await Future.wait([
      for (final feed in _feeds.values) _read(feed..failures = 0),
    ]);
  }

  /// Reads [instanceId] at the user's request. After a rejected sign-in this
  /// also has it try again, which nothing else here does.
  Future<void> retry(String instanceId) async {
    final feed = _feeds[instanceId];
    if (feed == null) return;
    if (!feed.rejected) return _read(feed..failures = 0);
    if (!_retrying.add(instanceId)) return;
    final services = ref.read(appServicesProvider);
    final readsBefore = feed.reads;
    try {
      await services.profiles.retryAuth(instanceId);
      await services.registry.refresh();
      if (_disposed) return;
      _reconcile(services.registry.scope);
      _publish();
      final now = _feeds[instanceId];
      // The reconciling starts the read where the instance is now another or
      // was latched.
      if (now != null &&
          !now.instance.instance.authFailed &&
          now.reading == null &&
          now.reads == (identical(now, feed) ? readsBefore : 0)) {
        now
          ..failure = null
          ..failures = 0;
        await _read(now);
      }
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      services.log.log(
        LogLevel.warning,
        'A sign-in could not be retried (${error.runtimeType})',
      );
    } finally {
      _retrying.remove(instanceId);
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
        // Figures that are no longer read are no longer live.
        feed.torrents = null;
      }
    }
    _publish();
  }

  /// Keeps what was read of the instances that are still the same, forgets the
  /// rest and takes up new ones.
  void _reconcile(ProfileScope? scope) {
    final providers =
        scope?.providers(CapabilityKind.downloadProgress) ?? const [];
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

  /// Reads [feed], or joins the read under way.
  Future<void> _read(_Feed feed) =>
      feed.reading ??= _readNow(feed).whenComplete(() => feed.reading = null);

  Future<void> _readNow(_Feed feed) async {
    // So that [_Feed.reading] is set before anything can finish.
    await null;
    if (_disposed || !identical(_feeds[feed.id], feed)) return;
    feed.timer?.cancel();
    if (feed.rejected) return;
    final scope = ref.read(appServicesProvider).registry.scope;
    if (scope == null) return;
    feed.reads += 1;
    Result<List<DownloadProgress>, ServiceFailure>? result;
    await for (final answer in scope.aggregate(
      CapabilityKind.downloadProgress,
      (provider) => provider.progress(),
      where: (instance, _) => instance.instance.id == feed.id,
    )) {
      result = answer.parts.firstOrNull?.result;
    }
    // No result: no longer current; the change of scope takes care of it.
    if (_disposed || !identical(_feeds[feed.id], feed) || result == null) {
      return;
    }
    switch (result) {
      case Ok(:final value):
        feed
          // Reading may have stopped while this was under way.
          ..torrents = _polling ? value : null
          ..failure = null
          ..failures = 0;
      case Err(:final error):
        feed
          ..torrents = null
          ..failure = error
          ..failures += 1;
    }
    _publish();
    if (_polling && !feed.rejected) {
      final pause = queuePollInterval * pow(2, min(feed.failures, 3)).toInt();
      feed.timer?.cancel();
      feed.timer = Timer(
        pause > queueMaxPollInterval ? queueMaxPollInterval : pause,
        () => unawaited(_read(feed)),
      );
    }
  }

  void _publish() {
    if (!_disposed) state = _snapshot();
  }

  ClientProgressState _snapshot() => ClientProgressState([
    for (final id in _order)
      if (_feeds[id] case final feed?)
        ClientProgress(
          instance: feed.instance,
          torrents: feed.torrents,
          failure:
              feed.failure ??
              (feed.instance.instance.authFailed ? const AuthFailed() : null),
        ),
  ]);
}

final class _Feed {
  _Feed(this.instance);

  ActiveInstance instance;
  List<DownloadProgress>? torrents;
  ServiceFailure? failure;

  /// Failed reads in a row.
  var failures = 0;

  /// Counts the reads sent.
  var reads = 0;

  Timer? timer;
  Future<void>? reading;

  String get id => instance.instance.id;

  /// Whether the sign-in was rejected, so that nothing may be sent.
  bool get rejected => instance.instance.authFailed || failure is AuthFailed;
}
