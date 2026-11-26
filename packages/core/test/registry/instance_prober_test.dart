/// Automatic probing (research R5).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../artwork/support.dart';
import '../network/support.dart';
import 'support.dart';

class FakeConnectivity implements NetworkConnectivity {
  final _changes = StreamController<NetworkStatus>.broadcast();
  var status = const NetworkStatus({NetworkTransport.wifi});

  @override
  Future<NetworkStatus> current() async => status;

  @override
  Stream<NetworkStatus> get changes => _changes.stream;

  void report(Set<NetworkTransport> transports) {
    status = NetworkStatus(transports);
    _changes.add(status);
  }
}

void main() {
  setUpImages();

  late World world;
  late GatedServer server;
  late FakeConnectivity network;
  late InstanceProber prober;

  InstanceProber probing(InstanceRegistry registry) {
    final prober = InstanceProber(
      registry: registry,
      modules: world.modules,
      profiles: world.profiles,
      connectivity: network,
      log: world.log,
    );
    addTearDown(prober.close);
    return prober..start();
  }

  setUp(() async {
    world = await World.start();
    server = await GatedServer.start('2');
    network = FakeConnectivity();
    prober = probing(world.registry);
  });

  InstanceRegistry registry() => world.registry;

  InstanceConnection connection(String id) => world.active(id).connection;

  Future<void> reaches<C extends InstanceConnection>(String id) =>
      _until(() => registry().scope?.instance(id)?.connection is C);

  /// Adds an instance that has not been probed.
  Future<String> add(
    String name,
    Uri url, {
    String? profileId,
    bool enabled = true,
  }) =>
      world.add(name, url, profileId: profileId, enabled: enabled, probe: null);

  /// Adds an instance that signs in, with a rejected login if [server] says no.
  Future<String> addClient(Uri url) async {
    final added = await world.profiles.addInstance(
      world.home,
      InstanceDraft(
        name: 'Client',
        serviceType: 'client',
        url: url,
        authKind: AuthKind.userPassword,
      ),
      credential: const Credential(username: 'zq-user', password: 'zq-pass'),
    );
    await registry().refresh();
    return (added as Ok<Instance, RuleViolation>).value.id;
  }

  group('an instance is probed', () {
    test('once when it is added, and what is found is kept', () async {
      final id = await add('First', server.url);

      await reaches<ConnectionOnline>(id);
      await _until(() => world.active(id).capabilities.isNotEmpty);

      final saved = (await world.profiles.instance(id))!;
      expect(saved.detectedVersion, '2');
      expect(saved.lastProbe!.capabilities, {CapabilityKind.health});
      await world.preferences.setTrueBlack(true);
      await registry().refresh();
      await pause();
      expect(server.calls, ['GET /status']);
    });

    test('at the first contact of each launch', () async {
      await prober.close();
      final id = await world.add('First', server.url);
      await registry().close();
      expect(server.calls, isEmpty);

      // The prober may be started before the registry.
      final later = world.newRegistry();
      probing(later);
      await later.start();

      await _until(
        () => later.scope!.instance(id)!.connection is ConnectionOnline,
      );
      expect(server.calls, ['GET /status']);
    });

    test('when its profile is activated, not before', () async {
      final away = await world.profile('Away');
      final id = await add('First', server.url, profileId: away);
      await pause();
      expect(server.calls, isEmpty);

      await registry().switchTo(away);
      await reaches<ConnectionOnline>(id);
      await registry().switchTo(world.home);
      await registry().switchTo(away);
      await reaches<ConnectionOnline>(id);

      expect(server.calls, ['GET /status', 'GET /status']);
    });

    test('when it is re-enabled, and not while disabled', () async {
      final id = await add('First', server.url, enabled: false);
      prober.probe(id);
      await pause();
      expect(server.calls, isEmpty);

      await world.edit(id, 'First', server.url);

      await reaches<ConnectionOnline>(id);
      expect(server.calls, ['GET /status']);
    });

    test('again when its address or credential changes', () async {
      final id = await add('First', server.url);
      await reaches<ConnectionOnline>(id);
      final other = await GatedServer.start('3');

      await world.edit(id, 'First', other.url);
      await reaches<ConnectionOnline>(id);
      await _until(() => world.active(id).instance.detectedVersion == '3');
      await world.edit(
        id,
        'First',
        other.url,
        credential: const Credential(apiKey: 'zq-other-key'),
      );
      await reaches<ConnectionOnline>(id);

      expect(server.calls, ['GET /status']);
      expect(other.calls, ['GET /status', 'GET /status']);
      expect(other.server.requests.last.headers['x-api-key'], 'zq-other-key');
    });

    test('when the user asks, once at a time', () async {
      final id = await add('First', server.url);
      await reaches<ConnectionOnline>(id);
      server.hold('status');

      prober.probe(id);
      prober.probe(id);
      await reaches<ConnectionProbing>(id);
      prober.probe(id);
      server.release('status');
      await reaches<ConnectionOnline>(id);

      expect(server.calls, ['GET /status', 'GET /status']);
    });
  });

  group('a failed probe', () {
    test('says why, keeps what was known and is not repeated', () async {
      server.statuses['status'] = 500;

      final id = await world.add('First', server.url);
      await reaches<ConnectionOffline>(id);
      // Reads are retried by the client; the probe itself is not.
      final sent = server.calls.length;
      await world.preferences.setTrueBlack(true);
      await registry().refresh();
      await pause();

      expect((connection(id) as ConnectionOffline).failure, isA<ServerError>());
      expect(world.active(id).capabilities, {CapabilityKind.health});
      expect(world.active(id).instance.detectedVersion, '1');
      expect(server.calls, hasLength(sent));
    });

    test('of a module that throws is a malformed response', () async {
      world.radarr.probeThrows = true;

      final id = await add('First', server.url);
      await reaches<ConnectionOffline>(id);

      expect(
        (connection(id) as ConnectionOffline).failure,
        isA<MalformedResponse>(),
      );
    });
  });

  group('a latched instance', () {
    test('is not probed until the user has it try again', () async {
      await prober.close();
      final id = await add('First', server.url);
      await world.profiles.markAuthFailed(id);
      await registry().refresh();

      prober = probing(registry());
      prober.probe(id);
      network.report({NetworkTransport.cellular});
      await pause();
      expect(server.calls, isEmpty);
      expect(connection(id), isA<ConnectionUnknown>());

      await world.profiles.retryAuth(id);

      await reaches<ConnectionOnline>(id);
      expect(server.calls, ['GET /status']);
    });

    test('by a rejected probe is left alone', () async {
      server.statuses['status'] = 401;

      final id = await add('First', server.url);
      await reaches<ConnectionOffline>(id);
      await _until(() => world.active(id).instance.authFailed);
      prober.probe(id);
      registry().resetConnections();
      await pause();
      expect(server.calls, ['GET /status']);

      // And once only for each retry.
      await world.profiles.retryAuth(id);
      await _until(() => server.calls.length == 2);
      await _until(() => world.active(id).instance.authFailed);
      await pause();

      expect(server.calls, ['GET /status', 'GET /status']);
    });

    test('that was offline is probed again on a retry', () async {
      final id = await add('First', server.url);
      await reaches<ConnectionOnline>(id);

      await world.profiles.markAuthFailed(id);
      await _until(() => world.active(id).instance.authFailed);
      await world.profiles.retryAuth(id);

      await _until(() => server.calls.length == 2);
      await reaches<ConnectionOnline>(id);
    });

    test('by a rejected login sends the password once', () async {
      final refusing = await GatedServer.start('no');

      final id = await addClient(refusing.url);
      await _until(() => world.active(id).instance.authFailed);
      registry().resetConnections();
      await pause();

      expect(refusing.calls, ['POST /login']);
    });
  });

  test('a probe does not repeat a sign-in that just failed', () async {
    final failing = await GatedServer.start();
    failing.statuses['login'] = 500;
    final id = await addClient(failing.url);
    await reaches<ConnectionOffline>(id);

    network.report({NetworkTransport.cellular});
    await pause();
    prober.probe(id);
    await pause();

    expect((connection(id) as ConnectionOffline).failure, isA<ServerError>());
    expect(failing.calls, ['POST /login']);
  });

  test('a slow instance does not hold up the others', () async {
    final slow = await GatedServer.start('2');
    slow.hold('status');
    final first = await add('Slow', slow.url);
    await slow.arrival('status');

    final second = await add('Second', server.url);
    await reaches<ConnectionOnline>(second);

    expect(connection(first), isA<ConnectionProbing>());
    slow.release('status');
    await reaches<ConnectionOnline>(first);
    expect(slow.calls, ['GET /status']);
  });

  group('a change of network', () {
    test('has every instance probed again', () async {
      final id = await add('First', server.url);
      await reaches<ConnectionOnline>(id);

      network.report({NetworkTransport.cellular});

      await _until(() => server.calls.length == 2);
      await reaches<ConnectionOnline>(id);
    });

    test('that only repeats the network there was does not', () async {
      final id = await add('First', server.url);
      await reaches<ConnectionOnline>(id);

      network.report({NetworkTransport.wifi});
      await pause();

      expect(connection(id), isA<ConnectionOnline>());
      expect(server.calls, ['GET /status']);
    });

    test('during a probe has it done once more, afterwards', () async {
      server.hold('status');
      final id = await add('First', server.url);
      await server.arrival('status');

      network.report({NetworkTransport.cellular});
      await pumpEventQueue();
      network.report({NetworkTransport.wifi});
      await pause();
      expect(server.calls, ['GET /status']);
      expect(connection(id), isA<ConnectionUnknown>());
      server.release('status');

      await reaches<ConnectionOnline>(id);
      await pause();
      expect(server.calls, ['GET /status', 'GET /status']);
    });
  });

  group('what is no longer current', () {
    test('is not recorded after a switch of profile', () async {
      final away = await world.profile('Away');
      server.hold('status');
      final id = await add('First', server.url);
      await server.arrival('status');

      await registry().switchTo(away);
      server.release('status');
      await pause();

      expect((await world.profiles.instance(id))!.lastProbe, isNull);
    });

    test('is not recorded after an edit, which is probed at once', () async {
      server.hold('status');
      final id = await add('First', server.url);
      await server.arrival('status');
      final other = await GatedServer.start('3');

      await world.edit(id, 'First', other.url);
      await reaches<ConnectionOnline>(id);
      server.release('status');
      await pause();

      expect((await world.profiles.instance(id))!.detectedVersion, '3');
      expect(connection(id), isA<ConnectionOnline>());
    });

    test('is not probed after close', () async {
      await prober.close();

      final id = await add('First', server.url);
      network.report({NetworkTransport.cellular});
      await pause();

      expect(connection(id), isA<ConnectionUnknown>());
      expect(server.calls, isEmpty);
    });
  });
}

/// Waits for something that happens on its own.
Future<void> _until(bool Function() done) async {
  final waited = Stopwatch()..start();
  while (!done()) {
    if (waited.elapsed > const Duration(seconds: 10)) fail('never happened');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
