import 'dart:async';
import 'dart:convert';

import '../artwork/artwork_cache.dart';
import '../cache/cache_repository.dart';
import '../instances/auth_kind.dart';
import '../instances/instance.dart';
import '../instances/probe_snapshot_json.dart';
import '../instances/profile_repository.dart';
import '../logging/diagnostic_log.dart';
import '../logging/log_level.dart';
import '../module/app_navigator.dart';
import '../module/instance_context.dart';
import '../module/service_module.dart';
import '../platform/local_network_permission.dart';
import '../preferences/preferences_repository.dart';
import '../session/instance_session.dart';
import 'active_instance.dart';
import 'instance_connection.dart';
import 'instance_lease.dart';
import 'module_registry.dart';
import 'profile_scope.dart';

/// Keeps the active profile's instances ready for use (research R5).
///
/// It follows what is saved through its [ProfileRepository], and builds a
/// context for every enabled instance of the active profile whose service type
/// is registered, and for no other. The app has one.
///
/// - After a switch of profile nothing more of the old one arrives: its reads
///   under way fail, its writes under way finish and report their outcome, and
///   nothing new is sent for it.
/// - The same happens to an instance that is edited, disabled or removed. An
///   edited one gets a new session.
/// - There is never more than one session in use for an instance.
/// - The artwork of an instance is cleared when its address changes or it is
///   removed, whatever its profile.
final class InstanceRegistry {
  /// [profiles] must have been made with the same [modules]. [timeout] is that
  /// of [InstanceSession].
  InstanceRegistry({
    required this._modules,
    required this._profiles,
    required this._preferences,
    required this._cache,
    required this._artwork,
    required this._navigator,
    required this._log,
    required this._localNetwork,
    this._timeout = const Duration(seconds: 30),
  });

  final ModuleRegistry _modules;
  final ProfileRepository _profiles;
  final PreferencesRepository _preferences;
  final CacheRepository _cache;
  final ArtworkCache _artwork;
  final AppNavigator _navigator;
  final DiagnosticLog _log;
  final LocalNetworkPermission _localNetwork;
  final Duration _timeout;

  final _scopes = StreamController<ProfileScope?>.broadcast();
  StreamSubscription<void>? _watch;

  /// The sessions not yet closed, the one in use for each instance.
  final _links = <String, SessionLink>{};

  /// Of the instances in the scope, by id and in its order.
  var _entries = <String, _Entry>{};

  /// One for each activation of a profile.
  _Activation? _activation;
  ProfileScope? _scope;

  /// The address of every instance of every profile, as last seen.
  var _addresses = <String, String>{};

  Future<void> _pending = Future.value();
  var _switching = 0;
  var _closed = false;

  /// The active profile's instances. Null before [start], while switching and
  /// without an active profile.
  ProfileScope? get scope => _scope;

  /// Every later change of [scope].
  Stream<ProfileScope?> get changes => _scopes.stream;

  /// Loads the active profile and follows later changes. Call once, after
  /// `ProfileRepository.ensureDefaultProfile`.
  Future<void> start() {
    if (_watch != null) throw StateError('Already started');
    _watch = _profiles.changes.listen(
      (_) => unawaited(
        refresh().catchError((Object error) {
          _warn('The profiles could not be read', error);
        }),
      ),
    );
    return refresh();
  }

  /// Applies what is saved now. Changes are followed without this; await it
  /// after saving one to go on only once [scope] has it.
  Future<void> refresh() => _enqueue(_reload);

  /// Makes [profileId] the active profile. [scope] is null, and the old
  /// profile's instances are no longer current, as soon as this is called.
  ///
  /// Throws what the database throws, for example for a profile that does not
  /// exist; the profile that is saved as active is then used again.
  Future<void> switchTo(String profileId) {
    _switching++;
    if (_activation != null && _activation?.profileId != profileId) {
      _deactivate();
      _publish(null);
    }
    return _enqueue(() async {
      try {
        await _preferences.setActiveProfile(profileId);
      } finally {
        _switching--;
        await _reload();
      }
    });
  }

  /// Records what a check of [instance] found. Ignored if it is no longer
  /// current, so that a late answer does not mark what replaced it.
  void setConnection(ActiveInstance instance, InstanceConnection connection) {
    if (!instance.isCurrent) return;
    final entry = _entries[instance.instance.id];
    if (entry == null) return;
    entry.active = entry.active.withConnection(connection);
    _publishEntries();
  }

  /// Marks every connection unknown, as after a change of network.
  void resetConnections() {
    if (_entries.isEmpty) return;
    for (final entry in _entries.values) {
      entry.active = entry.active.withConnection(const ConnectionUnknown());
    }
    _publishEntries();
  }

  /// Stops following changes and ends every instance's use. Writes under way
  /// still finish.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _deactivate();
    _scope = null;
    await _watch?.cancel();
    await _pending;
    await _scopes.close();
  }

  /// Runs [job] after those before it.
  Future<void> _enqueue(Future<void> Function() job) {
    final done = _pending.then((_) => job());
    // A failure is the caller's, and must not stop later jobs.
    _pending = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  Future<void> _reload() async {
    if (_closed) return;
    final activeId = (await _preferences.read()).activeProfileId;
    final instances = <Instance>[
      for (final profile in await _profiles.profiles())
        ...await _profiles.instances(profile.id),
    ];
    // A switch that is on its way reloads when it has been saved.
    if (_closed || _switching > 0) return;
    _apply(activeId, instances);
    // After the instances concerned have been retired.
    _clearArtwork(instances);
  }

  void _apply(String? profileId, List<Instance> instances) {
    final versions = {for (final saved in instances) saved.id: _version(saved)};
    var changed = false;
    if (_activation?.profileId != profileId) {
      _deactivate(versions);
      if (profileId != null) _activation = _Activation(profileId);
      changed = true;
    }
    if (profileId == null) {
      if (changed) _publish(null);
      return;
    }

    final wanted = [
      for (final saved in instances)
        if (saved.profileId == profileId &&
            saved.enabled &&
            _modules[saved.serviceType] != null)
          saved,
    ];
    final kept = <String, _Entry>{};
    for (final saved in wanted) {
      final old = _entries[saved.id];
      if (old != null && old.lease.link.version == versions[saved.id]) {
        kept[saved.id] = old;
      }
    }
    for (final MapEntry(key: id, value: entry) in _entries.entries) {
      if (kept.containsKey(id)) continue;
      entry.lease.retire(outdated: versions[id] != entry.lease.link.version);
      changed = true;
    }

    final entries = <String, _Entry>{};
    for (final saved in wanted) {
      final record = _record(saved);
      var entry = kept[saved.id];
      if (entry == null) {
        final module = _modules[saved.serviceType]!;
        final lease = InstanceLease(_link(saved, module));
        entry = _Entry(record, lease, _activate(saved, module, lease));
        changed = true;
      } else if (entry.record != record) {
        // The same session, as screens may still be using it.
        entry = _Entry(
          record,
          entry.lease,
          _activate(
            saved,
            entry.active.module,
            entry.lease,
          ).withConnection(entry.active.connection),
        );
        changed = true;
      }
      entries[saved.id] = entry;
    }
    final reordered = entries.keys.join() != _entries.keys.join();
    _entries = entries;
    if (changed || reordered) _publishEntries();
  }

  SessionLink _link(Instance instance, ServiceModule module) {
    final version = _version(instance);
    final open = _links[instance.id];
    if (open != null && open.version == version) return open..take();
    return _links[instance.id] = SessionLink(
      InstanceSession(
        profiles: _profiles,
        instanceId: instance.id,
        handler: module.sessionHandler,
        apiKeyHeader: module.descriptor.apiKeyHeader,
        log: _log,
        localNetwork: _localNetwork,
        timeout: _timeout,
      ),
      version: version,
      signsIn: _signsIn(instance, module),
      onClosed: (closed) {
        if (identical(_links[instance.id], closed)) _links.remove(instance.id);
      },
    );
  }

  ActiveInstance _activate(
    Instance instance,
    ServiceModule module,
    InstanceLease lease,
  ) => ActiveInstance(
    module: module,
    isCurrent: () => lease.isCurrent,
    context: InstanceContext(
      instance: instance,
      http: lease,
      artwork: _artwork.loaderFor(instance.id, lease),
      navigator: _navigator,
      cache: LeasedCache(_cache.scope(instance.id), lease),
      logger: _log,
      session: _signsIn(instance, module) ? lease : null,
    ),
  );

  static bool _signsIn(Instance instance, ServiceModule module) =>
      module.sessionHandler != null &&
      switch (instance.authKind) {
        AuthKind.userPassword || AuthKind.mediaServerAccount => true,
        AuthKind.apiKey || AuthKind.none => false,
      };

  /// Ends the active profile's use. [versions] are those saved now, where that
  /// is known.
  void _deactivate([Map<String, String>? versions]) {
    _activation?.ended = true;
    _activation = null;
    for (final MapEntry(key: id, value: entry) in _entries.entries) {
      entry.lease.retire(
        outdated: versions != null && versions[id] != entry.lease.link.version,
      );
    }
    _entries = {};
  }

  void _publishEntries() {
    final activation = _activation;
    if (activation == null) return;
    _publish(
      ProfileScope(
        profileId: activation.profileId,
        instances: List.unmodifiable([
          for (final entry in _entries.values) entry.active,
        ]),
        isCurrent: () => !activation.ended,
        log: _log,
      ),
    );
  }

  void _publish(ProfileScope? scope) {
    _scope = scope;
    if (!_scopes.isClosed) _scopes.add(scope);
  }

  void _clearArtwork(List<Instance> instances) {
    final addresses = {
      for (final instance in instances) instance.id: instance.url.toString(),
    };
    for (final MapEntry(key: id, value: address) in _addresses.entries) {
      if (addresses[id] == address) continue;
      unawaited(
        _artwork.clear(instanceId: id).catchError((Object error) {
          _warn('Artwork could not be cleared', error);
        }),
      );
    }
    _addresses = addresses;
  }

  // The type only: the text of an error may quote an address or a secret.
  void _warn(String message, Object error) =>
      _log.log(LogLevel.warning, '$message (${error.runtimeType})');

  /// What a session is made for. Every saved edit changes `updatedAt`, also
  /// one of the credential only.
  static String _version(Instance instance) => jsonEncode([
    instance.updatedAt.toIso8601String(),
    instance.url.toString(),
    instance.authKind.name,
    instance.certPin,
    instance.customCa,
  ]);

  /// What else of a record can change.
  static String _record(Instance instance) => jsonEncode([
    _version(instance),
    instance.name,
    instance.sortOrder,
    instance.authFailed,
    instance.detectedVersion,
    if (instance.lastProbe case final probe?) encodeProbeSnapshot(probe),
    for (final link in instance.links) [link.type.name, link.instanceId],
  ]);
}

final class _Activation {
  _Activation(this.profileId);

  final String profileId;
  var ended = false;
}

final class _Entry {
  _Entry(this.record, this.lease, this.active);

  final String record;
  final InstanceLease lease;

  /// Replaced when only its connection changes.
  ActiveInstance active;
}
