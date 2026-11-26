import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;

import '../instances/probe_snapshot.dart';
import '../instances/profile_repository.dart';
import '../logging/diagnostic_log.dart';
import '../logging/log_level.dart';
import '../module/result.dart';
import '../module/service_failure.dart';
import '../network/service_http_client.dart';
import '../platform/network_connectivity.dart';
import '../platform/network_status.dart';
import '../platform/network_transport.dart';
import 'active_instance.dart';
import 'instance_connection.dart';
import 'instance_registry.dart';
import 'module_registry.dart';
import 'profile_scope.dart';

/// Probes the active profile's instances without being asked (research R5).
///
/// Every instance of the [InstanceRegistry]'s scope whose connection is unknown
/// is probed. That is so at the first contact of a launch, after a profile is
/// activated, an instance is added, imported, re-enabled or edited, and after a
/// change of network. A latched instance is also probed once the user has it
/// try again. What a successful probe found is kept, as is that a server's
/// version is too old, and the instance's connection says how it went.
///
/// - Nothing is sent for an instance whose `authFailed` is set, nor for one that
///   is disabled or not of the active profile.
/// - A failed probe is not repeated until one of the above happens again, or the
///   app asks with [probe].
/// - Instances are probed at the same time, and one has at most one probe under
///   way.
///
/// The app has one.
final class InstanceProber {
  /// [registry] must have been made with the same [modules] and [profiles].
  InstanceProber({
    required this._registry,
    required this._modules,
    required this._profiles,
    required this._connectivity,
    required this._log,
  });

  final InstanceRegistry _registry;
  final ModuleRegistry _modules;
  final ProfileRepository _profiles;
  final NetworkConnectivity _connectivity;
  final DiagnosticLog _log;

  StreamSubscription<ProfileScope?>? _scopes;
  StreamSubscription<NetworkStatus>? _network;

  /// The clients of the instances being probed. An edited instance has another
  /// one, so a probe of what it was does not keep it from being probed.
  final _underWay = <ServiceHttpClient>{};

  /// The ids last seen latched.
  final _latched = <String>{};

  /// The network as last seen.
  Set<NetworkTransport>? _transports;
  var _closed = false;

  /// Probes what is unknown now and later. Call once, before or after
  /// `InstanceRegistry.start`.
  void start() {
    if (_scopes != null) throw StateError('Already started');
    _scopes = _registry.changes.listen((_) => _probeUnknown());
    _network = _connectivity.changes.listen(
      _onNetwork,
      onError: (Object error) => _warn('The network could not be read', error),
    );
    unawaited(_readNetwork());
    _probeUnknown();
  }

  /// Probes one instance now, for a retry the user asks for or when the app
  /// returns to the foreground. Does nothing if it is not in the scope, is being probed or is latched: to have a latched one
  /// try again, call `ProfileRepository.retryAuth`. Like any request it does not
  /// repeat a sign-in that failed moments ago (see `InstanceSession`).
  void probe(String instanceId) {
    final active = _registry.scope?.instance(instanceId);
    if (active == null || active.instance.authFailed) return;
    unawaited(_probe(active));
  }

  /// Stops probing. What is under way is not recorded.
  Future<void> close() async {
    _closed = true;
    await _scopes?.cancel();
    await _network?.cancel();
  }

  void _probeUnknown() {
    if (_closed) return;
    for (final active in _registry.scope?.instances ?? <ActiveInstance>[]) {
      final id = active.instance.id;
      if (active.instance.authFailed) {
        _latched.add(id);
        continue;
      }
      var unknown = active.connection is ConnectionUnknown;
      // The user has it try again: what was found before no longer holds.
      if (_latched.remove(id) && !unknown) {
        _registry.setConnection(active, const ConnectionUnknown());
        unknown = true;
      }
      if (unknown) unawaited(_probe(active));
    }
  }

  Future<void> _probe(ActiveInstance active) async {
    final client = active.context.http;
    if (_closed || !_underWay.add(client)) return;
    var reset = false;
    try {
      reset = await _check(active);
    } catch (error) {
      _warn('An instance could not be checked', error);
      _registry.setConnection(active, const ConnectionOffline(Unreachable()));
    } finally {
      _underWay.remove(client);
    }
    if (reset) _probeUnknown();
  }

  /// Probes [active] and records the outcome. True if its connection was reset
  /// meanwhile, so that the answer is from before and it must be probed again.
  Future<bool> _check(ActiveInstance active) async {
    final id = active.instance.id;
    // Read first, so that what is recorded is known to be what was probed.
    final used = await _profiles.instanceWithCredential(id);
    if (used == null || _closed || !active.isCurrent) return false;
    final saved = used.instance;
    // Latched, or edited or disabled and the registry has yet to apply it.
    if (saved.authFailed ||
        !saved.enabled ||
        saved.updatedAt != active.instance.updatedAt) {
      return false;
    }

    _registry.setConnection(active, const ConnectionProbing());
    final answer = await _ask(active);
    if (_closed || !active.isCurrent) return false;
    try {
      final recorded = switch (answer) {
        Ok(:final value) => await _profiles.recordProbe(used, value),
        Err(error: UnsupportedVersion(:final version)) =>
          await _profiles.recordUnsupportedVersion(used, version),
        // Any other failure says nothing about the server.
        Err() => true,
      };
      // Edited meanwhile: the registry is about to replace the instance.
      if (!recorded) return false;
    } catch (error) {
      // The server answered all the same.
      _warn('A probe could not be recorded', error);
    }
    if (!active.isCurrent) return false;
    if (_registry.scope?.instance(id)?.connection is! ConnectionProbing) {
      return true;
    }
    _registry.setConnection(active, switch (answer) {
      Ok() => const ConnectionOnline(),
      Err(:final error) => ConnectionOffline(error),
    });
    return false;
  }

  /// What to keep of a probe of [active], or why it failed.
  Future<Result<ProbeSnapshot, ServiceFailure>> _ask(
    ActiveInstance active,
  ) async {
    try {
      return switch (await active.module.probe(active.context)) {
        Ok(:final value) => Ok(
          _modules.snapshotOf(active.instance.serviceType, value),
        ),
        Err(:final error) => Err(error),
      };
    } catch (error, stackTrace) {
      // The type only: the text may quote an address or a secret.
      _log.log(
        LogLevel.error,
        'A module failed to probe (${error.runtimeType})',
        stackTrace: stackTrace,
      );
      return const Err(MalformedResponse());
    }
  }

  Future<void> _readNetwork() async {
    try {
      final status = await _connectivity.current();
      _transports ??= status.transports;
    } catch (error) {
      _warn('The network could not be read', error);
    }
  }

  void _onNetwork(NetworkStatus status) {
    final before = _transports;
    _transports = status.transports;
    // A new listener may first be told the network the device already has.
    if (before == null || setEquals(before, status.transports)) return;
    _registry.resetConnections();
  }

  void _warn(String message, Object error) =>
      _log.log(LogLevel.warning, '$message (${error.runtimeType})');
}
