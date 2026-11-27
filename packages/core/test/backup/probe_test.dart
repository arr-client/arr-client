/// What is imported is probed without being asked (research R5).
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../artwork/support.dart';
import '../registry/instance_prober_test.dart' show FakeConnectivity;
import '../registry/support.dart';
import 'support.dart' show encryptedFile, instanceJson, ok, passphrase;
import 'support.dart' show payload, profileJson, uuid;

void main() {
  setUpImages();

  late World world;
  late GatedServer server;
  late SetupBackup backup;

  setUp(() async {
    world = await World.start();
    server = await GatedServer.start('2');
    final prober = InstanceProber(
      registry: world.registry,
      modules: world.modules,
      profiles: world.profiles,
      connectivity: FakeConnectivity(),
      log: world.log,
    );
    addTearDown(prober.close);
    prober.start();
    backup = SetupBackup(
      database: world.database,
      profiles: world.profiles,
      preferences: world.preferences,
      secrets: world.secrets,
      log: world.log,
      modules: [world.radarr, world.client],
    );
  });

  Future<void> import(String key) async {
    final file = await encryptedFile(
      payload(
        profiles: [profileJson(1, 'Restored')],
        instances: [
          instanceJson(
            2,
            'Movies',
            profile: 1,
            url: '${server.url}',
            credential: {'apiKey': key},
          ),
        ],
      ),
    );
    final read = ok(await backup.read(file, passphrase: passphrase));
    ok(await backup.apply(ok(await backup.preview(read))));
    await world.registry.refresh();
  }

  /// The API keys the probes were sent with.
  List<String?> probes() => [
    for (final request in server.server.requests)
      if (request.target == '/status') request.headers['x-api-key'],
  ];

  Future<void> online() async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (world.registry.scope?.instance(uuid(2))?.connection
        is! ConnectionOnline) {
      if (DateTime.now().isAfter(end)) fail('Not probed');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('after an import, with the imported credential', () async {
    await import('zq-first');
    await online();

    expect(probes(), ['zq-first']);
  });

  test('again after an import replaces it, also if latched', () async {
    await import('zq-first');
    await online();
    await world.profiles.markAuthFailed(uuid(2));
    await world.registry.refresh();

    await import('zq-second');
    await online();

    expect(probes(), ['zq-first', 'zq-second']);
  });
}
