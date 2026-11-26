/// The composition root: everything the app runs on is made here, once.
library;

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'modules.dart';
import 'navigation/router_app_navigator.dart';
import 'platform/connectivity.dart';
import 'platform/local_network.dart';
import 'platform/secret_store.dart';

/// Starts the app's services on the device's own.
Future<AppServices> startOnDevice() async {
  final directory = await getApplicationSupportDirectory();
  return AppServices.start(
    // No part of the app's data is backed up (res/xml).
    database: NativeDatabase.createInBackground(
      File('${directory.path}/arr_client.sqlite'),
      // SQLite finds no directory for temporary files on Android.
      setup: (database) => database.execute('PRAGMA temp_store = MEMORY'),
    ),
    secrets: const KeystoreSecretStore(),
    connectivity: DeviceNetworkConnectivity(),
    localNetwork: DeviceLocalNetworkPermission(),
    cacheDirectory: getApplicationCacheDirectory,
  );
}

/// The services of a running app.
final class AppServices {
  AppServices._({
    required this.database,
    required this.log,
    required this.modules,
    required this.preferences,
    required this.profiles,
    required this.cache,
    required SecretStore secrets,
    required NetworkConnectivity connectivity,
    required this.localNetwork,
    required Future<Directory> Function() cacheDirectory,
  }) {
    artwork = ArtworkCache(
      directory: cacheDirectory,
      loadRemote: () => currentPreferences.loadThirdPartyArtwork,
    );
    registry = InstanceRegistry(
      modules: modules,
      profiles: profiles,
      preferences: preferences,
      cache: cache,
      artwork: artwork,
      navigator: navigator,
      log: log,
      localNetwork: localNetwork,
    );
    prober = InstanceProber(
      registry: registry,
      modules: modules,
      profiles: profiles,
      connectivity: connectivity,
      log: log,
    );
  }

  /// Makes the services, creates the first profile if there is none, loads the
  /// active one and begins probing its instances. If that fails, what was
  /// opened is closed again and the error is thrown.
  static Future<AppServices> start({
    required QueryExecutor database,
    required SecretStore secrets,
    required NetworkConnectivity connectivity,
    required LocalNetworkPermission localNetwork,
    required Future<Directory> Function() cacheDirectory,
    Iterable<ServiceModule>? modules,
  }) async {
    final log = DiagnosticLog();
    final registered = ModuleRegistry(modules ?? serviceModules());
    final store = AppDatabase(database);
    final preferences = PreferencesRepository(store);
    final services = AppServices._(
      database: store,
      log: log,
      modules: registered,
      preferences: preferences,
      profiles: ProfileRepository(
        database: store,
        secrets: secrets,
        log: log,
        preferences: preferences,
        modules: registered.modules,
      ),
      cache: CacheRepository(store),
      secrets: secrets,
      connectivity: connectivity,
      localNetwork: localNetwork,
      cacheDirectory: cacheDirectory,
    );
    try {
      await services._start();
      return services;
    } catch (_) {
      await services.close();
      rethrow;
    }
  }

  /// The database under the repositories.
  final AppDatabase database;

  /// The diagnostic log.
  final DiagnosticLog log;

  /// The registered modules.
  final ModuleRegistry modules;

  /// The operating system's local network permission.
  final LocalNetworkPermission localNetwork;

  /// The user's preferences.
  final PreferencesRepository preferences;

  /// Profiles and their instances.
  final ProfileRepository profiles;

  /// What was last read from the servers.
  final CacheRepository cache;

  /// The shared flows module screens ask for.
  final navigator = RouterAppNavigator();

  /// The artwork of every instance.
  late final ArtworkCache artwork;

  /// The active profile's instances.
  late final InstanceRegistry registry;

  /// Probes them without being asked.
  late final InstanceProber prober;

  /// The preferences as last read.
  var currentPreferences = const Preferences();

  StreamSubscription<Preferences>? _watch;

  Future<void> _start() async {
    await profiles.ensureDefaultProfile();
    currentPreferences = await preferences.read();
    _watch = preferences.watch().listen(
      (value) => currentPreferences = value,
      onError: (Object error) =>
          _warn('The preferences could not be read', error),
    );
    // Before the registry starts, so that it sees the first scope.
    prober.start();
    await registry.start();
  }

  /// Catches up with what was saved while the app was in the background.
  Future<void> resume() async {
    try {
      await registry.refresh();
    } catch (error) {
      _warn('The profiles could not be read', error);
    }
  }

  /// Stops everything. Writes under way still finish.
  Future<void> close() async {
    await prober.close();
    await registry.close();
    await _watch?.cancel();
    await artwork.close();
    await database.close();
  }

  // The type only: the text of an error may quote an address or a secret.
  void _warn(String message, Object error) =>
      log.log(LogLevel.warning, '$message (${error.runtimeType})');
}
