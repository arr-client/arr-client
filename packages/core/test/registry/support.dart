/// A registry over a database in memory, with modules that read a test server.
library;

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';

import '../artwork/support.dart';
import '../network/support.dart';

/// Reports the body of `GET health` as one problem.
class FakeHealth implements HealthProvider {
  FakeHealth(this.context);

  final InstanceContext context;

  @override
  bool get providesDiskSpace => false;

  @override
  ServiceResult<List<HealthIssue>> health() async =>
      switch (await context.http.send(get('health'))) {
        Ok(:final value) => Ok([
          HealthIssue(
            source: context.instance.name,
            level: HealthLevel.warning,
            message: value.text,
          ),
        ]),
        Err(:final error) => Err(error.failure),
      };

  @override
  ServiceResult<List<DiskSpace>> diskSpace() async => const Ok([]);
}

/// Signs in with `POST login`; whatever comes back but `no` is the session.
class FakeSessionHandler implements SessionHandler {
  @override
  ServiceResult<String> login({
    required AuthKind authKind,
    required Credential credential,
    required ServiceHttpClient http,
  }) async => switch (await http.send(request(HttpMethod.post, 'login'))) {
    Ok(:final value) when value.text == 'no' => const Err(AuthFailed()),
    Ok() => const Ok('SID=zq-session'),
    Err(:final error) => Err(error.failure),
  };

  @override
  bool isSessionExpired(ServiceResponse response) => response.statusCode == 403;
}

class FakeModule implements ServiceModule {
  FakeModule(this.id, {this.sessionHandler});

  @override
  final String id;

  /// How many capabilities have been built.
  var built = 0;

  /// Makes building a capability throw for the instance of this name.
  String? brokenFor;

  /// Makes every probe throw.
  var probeThrows = false;

  /// Reports the body of `GET status` as the version.
  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) async {
    if (probeThrows) throw StateError('broken');
    return switch (await context.http.send(get('status'))) {
      Ok(:final value) => Ok(ProbeResult(product: 'Fake', version: value.text)),
      Err(:final error) => Err(error.failure),
    };
  }

  @override
  ModuleDescriptor get descriptor => ModuleDescriptor(
    displayName: 'Fake',
    icon: const IconData(0),
    category: ModuleCategory.movies,
    authKinds: [
      sessionHandler == null ? AuthKind.apiKey : AuthKind.userPassword,
    ],
    apiKeyHeader: apiKeyHeader,
    defaultPort: 80,
    minimumVersion: '1',
    testedVersion: '1',
  );

  @override
  final SessionHandler? sessionHandler;

  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => {CapabilityKind.health};

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    if (context.instance.name == brokenFor) throw StateError('broken');
    if (T != HealthProvider) return null;
    built++;
    return FakeHealth(context) as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Navigator implements AppNavigator {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const healthy = ProbeSnapshot(
  product: 'Fake',
  version: '1',
  capabilities: {CapabilityKind.health},
);

/// A server that holds back the answer to every path in [held] until released.
class GatedServer {
  GatedServer._(this.body);

  late final TestServer server;
  final String body;
  final held = <String, Completer<void>>{};

  /// Paths answered with another status than 200.
  final statuses = <String, int>{};
  final _arrived = <String, Completer<void>>{};

  static Future<GatedServer> start([String body = 'fine']) async {
    final gated = GatedServer._(body);
    gated.server = await TestServer.start(gated._answer);
    addTearDown(() {
      for (final gate in gated.held.values) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    return gated;
  }

  Uri get url => server.url();

  /// What arrived.
  List<String> get calls => [
    for (final received in server.requests)
      '${received.method} ${received.target}',
  ];

  void hold(String path) => held[path] = Completer();

  void release(String path) => held[path]!.complete();

  /// Completes when a request for [path] has arrived.
  Future<void> arrival(String path) =>
      _arrived.putIfAbsent(path, Completer.new).future;

  Future<void> _answer(Received received, HttpResponse response) async {
    final path = received.target.substring(1).split('?').first;
    final arrived = _arrived.putIfAbsent(path, Completer.new);
    if (!arrived.isCompleted) arrived.complete();
    await held[path]?.future;
    try {
      await reply(
        response,
        status: statuses[path] ?? 200,
        body: body,
        contentType: 'text/plain',
      );
    } on Exception {
      // The client has gone.
    }
  }
}

class World {
  World._();

  final radarr = FakeModule('radarr');
  final client = FakeModule('client', sessionHandler: FakeSessionHandler());
  final secrets = MemorySecrets();
  final log = DiagnosticLog();
  final database = AppDatabase(NativeDatabase.memory());
  final directory = temporaryDirectory();

  late final modules = ModuleRegistry([radarr, client]);
  late final preferences = PreferencesRepository(database);
  late final profiles = ProfileRepository(
    database: database,
    secrets: secrets,
    log: log,
    preferences: preferences,
    // `gone` stands for a module that a later build no longer has.
    modules: [radarr, client, FakeModule('gone')],
  );
  late final cache = CacheRepository(database);
  late final artwork = cacheIn(directory);
  late final InstanceRegistry registry;

  /// The profile made at first launch.
  late final String home;

  static Future<World> start() async {
    final world = World._();
    addTearDown(world.database.close);
    await world.profiles.ensureDefaultProfile();
    world.home = (await world.profiles.profiles()).single.id;
    world.registry = world.newRegistry();
    await world.registry.start();
    return world;
  }

  InstanceRegistry newRegistry() {
    final registry = InstanceRegistry(
      modules: modules,
      profiles: profiles,
      preferences: preferences,
      cache: cache,
      artwork: artwork,
      navigator: _Navigator(),
      log: log,
      localNetwork: FakePermission(),
      timeout: const Duration(seconds: 10),
    );
    addTearDown(registry.close);
    return registry;
  }

  Future<String> profile(String name) async => ((await profiles.createProfile(
    name,
  )) as Ok<Profile, RuleViolation>).value.id;

  InstanceDraft draft(
    String name,
    Uri url, {
    String serviceType = 'radarr',
    bool enabled = true,
    ProbeSnapshot? probe = healthy,
  }) => InstanceDraft(
    name: name,
    serviceType: serviceType,
    url: url,
    authKind: AuthKind.apiKey,
    enabled: enabled,
    probe: probe,
  );

  /// Adds an instance and waits for the registry to have it.
  Future<String> add(
    String name,
    Uri url, {
    String? profileId,
    String serviceType = 'radarr',
    bool enabled = true,
    ProbeSnapshot? probe = healthy,
  }) async {
    final added = await profiles.addInstance(
      profileId ?? home,
      draft(
        name,
        url,
        serviceType: serviceType,
        enabled: enabled,
        probe: probe,
      ),
      credential: const Credential(apiKey: apiKey),
    );
    await registry.refresh();
    return (added as Ok<Instance, RuleViolation>).value.id;
  }

  Future<void> edit(
    String id,
    String name,
    Uri url, {
    bool enabled = true,
    Credential? credential,
  }) async {
    final result = await profiles.updateInstance(
      id,
      draft(name, url, enabled: enabled, probe: null),
      credential: credential,
    );
    expect(result, isA<Ok<Instance, RuleViolation>>());
    await registry.refresh();
  }

  ActiveInstance active(String id) => registry.scope!.instance(id)!;
}

/// Matches a send that failed with [F].
Matcher failsWith<F extends ServiceFailure>() =>
    isA<Err<ServiceResponse, HttpError>>().having(
      (result) => result.error.failure,
      'failure',
      isA<F>(),
    );

final succeeds = isA<Ok<ServiceResponse, HttpError>>();
