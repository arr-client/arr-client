/// The app's services over a database in memory, with modules that need no
/// server.
library;

import 'dart:async';
import 'dart:io';

import 'package:arr_client/app/app.dart';
import 'package:arr_client/app/composition.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeConnectivity implements NetworkConnectivity {
  @override
  Future<NetworkStatus> current() async =>
      const NetworkStatus({NetworkTransport.wifi});

  @override
  Stream<NetworkStatus> get changes => const Stream.empty();
}

class FakePermission implements LocalNetworkPermission {
  @override
  Future<LocalNetworkPermissionState> status(String host) async =>
      LocalNetworkPermissionState.notRequired;

  @override
  Future<LocalNetworkPermissionState> request(String host) async =>
      LocalNetworkPermissionState.notRequired;
}

class _Library implements LibraryProvider {
  _Library(this.itemKind);

  @override
  final MediaKind itemKind;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements RequestProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Subtitles implements SubtitleProvider {
  _Subtitles(this.instanceId);

  final String instanceId;

  @override
  ModuleRoute entryRoute() =>
      ModuleRoute(instanceId: instanceId, path: 'subtitles/browse');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A service whose probe always finds [offers].
class FakeModule implements ServiceModule {
  FakeModule(
    this.id, {
    required this.offers,
    this.itemKind = MediaKind.movie,
    this.permissions = const {},
  });

  @override
  final String id;

  final Set<CapabilityKind> offers;
  final MediaKind itemKind;
  final Set<ServicePermission> permissions;

  /// What a saved instance of this service was last found to offer.
  ProbeSnapshot get snapshot => ProbeSnapshot(
    product: id,
    version: '1',
    capabilities: offers,
    permissions: permissions,
  );

  @override
  ModuleDescriptor get descriptor => ModuleDescriptor(
    displayName: id,
    icon: Icons.dns,
    category: ModuleCategory.movies,
    authKinds: const [AuthKind.apiKey],
    apiKeyHeader: const ApiKeyHeader('X-Api-Key'),
    defaultPort: 80,
    minimumVersion: '1',
    testedVersion: '1',
  );

  @override
  SessionHandler? get sessionHandler => null;

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) async => Ok(
    ProbeResult(
      product: id,
      version: '1',
      session: SessionInfo(permissions: permissions),
    ),
  );

  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => offers;

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (LibraryProvider) => _Library(itemKind),
      const (RequestProvider) => _Request(),
      const (SubtitleProvider) => _Subtitles(context.instance.id),
      _ => null,
    };
    return found as T?;
  }

  @override
  List<ModuleScreen> routes() => [
    ModuleScreen(
      path: '$id/items/:itemId',
      builder: (context, instance, parameters) => Scaffold(
        body: Text(
          '${instance.instance.name} item ${parameters['itemId']} '
          '${parameters['from']}',
        ),
      ),
    ),
  ];
}

final movies = FakeModule(
  'movies',
  offers: {
    CapabilityKind.library,
    CapabilityKind.lookup,
    CapabilityKind.queue,
    CapabilityKind.history,
  },
);

final series = FakeModule(
  'series',
  itemKind: MediaKind.series,
  offers: {CapabilityKind.library, CapabilityKind.calendar},
);

final subtitles = FakeModule('subtitles', offers: {CapabilityKind.subtitle});

final downloads = FakeModule(
  'downloads',
  offers: {CapabilityKind.downloadProgress},
);

/// A running app without a device.
class TestApp {
  TestApp._(this.services);

  final AppServices services;

  static Future<TestApp> start(
    WidgetTester tester, {
    Iterable<ServiceModule>? modules,
  }) async {
    final services = await AppServices.start(
      database: NativeDatabase.memory(),
      secrets: MemorySecrets(),
      connectivity: FakeConnectivity(),
      localNetwork: FakePermission(),
      cacheDirectory: () async => Directory('build/test-cache'),
      modules: modules ?? [movies, series, subtitles, downloads],
    );
    return TestApp._(services);
  }

  Future<String> get activeProfile async =>
      (await services.preferences.read()).activeProfileId!;

  Future<String> addProfile(String name) async =>
      ((await services.profiles.createProfile(
        name,
      )) as Ok<Profile, RuleViolation>).value.id;

  /// Saves an instance already probed, in the active profile unless told.
  Future<String> add(
    FakeModule module,
    String name, {
    String? profileId,
    bool enabled = true,
  }) async {
    final added = await services.profiles.addInstance(
      profileId ?? await activeProfile,
      InstanceDraft(
        name: name,
        serviceType: module.id,
        url: Uri.parse('http://server.invalid/$name'),
        authKind: AuthKind.apiKey,
        enabled: enabled,
        probe: module.snapshot,
      ),
      credential: const Credential(apiKey: 'zq-key-0123456789'),
    );
    await services.registry.refresh();
    return (added as Ok<Instance, RuleViolation>).value.id;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ArrClientApp(services: services));
    await tester.pumpAndSettle();
  }

  /// Takes the app down and stops its services.
  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    var closed = false;
    unawaited(services.close().then((_) => closed = true));
    await settle(tester, until: () => closed);
    expect(closed, isTrue, reason: 'the services did not close');
  }
}

/// Runs both the test's clock, on which the database closes its queries, and
/// the real one: cancelling some streams completes only there.
Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 20 && !(until?.call() ?? false); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 10));
  }
}
