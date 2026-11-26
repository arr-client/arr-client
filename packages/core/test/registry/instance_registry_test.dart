/// The module registry, active-profile scoping, switching (research R5) and
/// persisted probe results.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../artwork/support.dart';
import '../network/support.dart';
import 'support.dart';

void main() {
  setUpImages();

  late World world;
  late GatedServer server;

  setUp(() async {
    world = await World.start();
    server = await GatedServer.start();
  });

  InstanceRegistry registry() => world.registry;

  group('modules', () {
    test('cannot share an id', () {
      expect(
        () => ModuleRegistry([FakeModule('radarr'), FakeModule('radarr')]),
        throwsArgumentError,
      );
    });

    test('turn a probe into what is kept', () {
      final snapshot = world.modules.snapshotOf(
        'radarr',
        const ProbeResult(
          product: 'Fake',
          version: '2',
          session: SessionInfo(permissions: {ServicePermission.requestMovies}),
        ),
      );

      expect(snapshot.version, '2');
      expect(snapshot.capabilities, {CapabilityKind.health});
      expect(snapshot.permissions, {ServicePermission.requestMovies});
      expect(
        () => world.modules.snapshotOf(
          'other',
          const ProbeResult(product: 'x', version: '1'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('the scope', () {
    test('has the enabled, known instances of the active profile', () async {
      final away = await world.profile('Away');
      final first = await world.add('First', server.url);
      await world.add('Disabled', server.url, enabled: false);
      await world.add('Unknown', server.url, serviceType: 'gone');
      await world.add('Elsewhere', server.url, profileId: away);
      final second = await world.add('Second', server.url);

      expect(registry().scope!.profileId, world.home);
      expect(
        [for (final active in registry().scope!.instances) active.instance.id],
        [first, second],
      );
    });

    test('follows what is saved without being asked', () async {
      final changed = registry().changes.first;

      await world.profiles.addInstance(
        world.home,
        world.draft('First', server.url),
      );

      expect((await changed)!.instances, hasLength(1));
    });

    test('is not given again when nothing about it changed', () async {
      await world.add('First', server.url);
      final scope = registry().scope;

      await world.preferences.setTrueBlack(true);
      await registry().refresh();

      expect(registry().scope, same(scope));
    });

    test('offers nothing of an instance that was never probed', () async {
      final id = await world.add('First', server.url, probe: null);

      expect(world.active(id).capabilities, isEmpty);
      expect(world.active(id).capability(CapabilityKind.health), isNull);
      expect(registry().scope!.providers(CapabilityKind.health), isEmpty);
      expect(world.radarr.built, 0);
    });

    test('offers what the last probe found, without a request', () async {
      final id = await world.add('First', server.url);

      // As at an offline launch.
      final later = world.newRegistry();
      await later.start();

      expect(later.scope!.capabilities, {CapabilityKind.health});
      final active = later.scope!.instance(id)!;
      expect(active.capability(CapabilityKind.health), isNotNull);
      expect(
        active.capability(CapabilityKind.health),
        same(active.capability(CapabilityKind.health)),
      );
      expect(active.capability(CapabilityKind.queue), isNull);
      expect(server.calls, isEmpty);
    });

    test('keeps a probe that is recorded, in the same session', () async {
      final id = await world.add('First', server.url, probe: null);
      final before = world.active(id);
      final used = (await world.profiles.instanceWithCredential(id))!;

      expect(await world.profiles.recordProbe(used, healthy), isTrue);
      await registry().refresh();

      final after = world.active(id);
      expect(after.capabilities, {CapabilityKind.health});
      expect(after.instance.detectedVersion, '1');
      expect(after.instance.updatedAt, before.instance.updatedAt);
      expect(before.isCurrent, isTrue);
      expect(await before.context.http.send(get('health')), succeeds);
    });

    test('does not keep the probe of an address edited meanwhile', () async {
      final id = await world.add('First', server.url, probe: null);
      final used = (await world.profiles.instanceWithCredential(id))!;
      await world.edit(id, 'First', server.url.resolve('/other'));

      expect(await world.profiles.recordProbe(used, healthy), isFalse);

      expect((await world.profiles.instance(id))!.lastProbe, isNull);
    });

    test('keeps the session when an instance is latched', () async {
      final id = await world.add('First', server.url);
      final before = world.active(id);

      await world.profiles.markAuthFailed(id);
      await registry().refresh();

      expect(world.active(id).instance.authFailed, isTrue);
      expect(before.isCurrent, isTrue);
      expect(await before.context.http.send(get('a')), failsWith<AuthFailed>());
      expect(server.calls, isEmpty);
    });
  });

  group('switching profile', () {
    late String away;
    late String id;
    late GatedServer other;

    setUp(() async {
      away = await world.profile('Away');
      id = await world.add('First', server.url);
      other = await GatedServer.start('away');
      await world.add('First', other.url, profileId: away);
    });

    test('ends the old one at once and builds the new one', () async {
      final scope = registry().scope!;
      final active = world.active(id);

      final switched = registry().switchTo(away);

      expect(registry().scope, isNull);
      expect(scope.isCurrent, isFalse);
      expect(active.isCurrent, isFalse);
      await switched;
      expect(registry().scope!.profileId, away);
      expect((await world.preferences.read()).activeProfileId, away);
      expect(registry().scope!.instances.single.instance.url, other.url);
    });

    test('cancels a read under way', () async {
      server.hold('slow');
      final read = world.active(id).context.http.send(get('slow'));
      await server.arrival('slow');

      final switched = registry().switchTo(away);

      // Before the server has answered.
      expect(await read, failsWith<Unreachable>());
      await switched;
    });

    test('lets a write under way finish, once', () async {
      server.hold('command');
      final context = world.active(id).context;
      final write = context.http.send(request(HttpMethod.post, 'command'));
      await server.arrival('command');

      await registry().switchTo(away);
      server.release('command');

      expect(await write, succeeds);
      expect(server.calls, ['POST /command']);
    });

    test('sends nothing more for the old one', () async {
      final context = world.active(id).context;
      await registry().switchTo(away);

      expect(await context.http.send(get('a')), failsWith<Unreachable>());
      expect(
        await context.http.send(request(HttpMethod.post, 'b')),
        failsWith<Unreachable>(),
      );
      expect(server.calls, isEmpty);
    });

    test('and back works while a write is still under way', () async {
      server.hold('command');
      final write = world
          .active(id)
          .context
          .http
          .send(request(HttpMethod.post, 'command'));
      await server.arrival('command');

      await registry().switchTo(away);
      await registry().switchTo(world.home);
      final read = await world.active(id).context.http.send(get('a'));
      server.release('command');

      expect(read, succeeds);
      expect(await write, succeeds);
      // The write has not closed the session that is in use again.
      expect(await world.active(id).context.http.send(get('b')), succeeds);
    });

    test('twice in a row shows only the last', () async {
      final third = await world.profile('Third');
      final seen = <String?>[];
      final subscription = registry().changes.listen(
        (scope) => seen.add(scope?.profileId),
      );
      addTearDown(subscription.cancel);

      await Future.wait([
        registry().switchTo(away),
        registry().switchTo(third),
      ]);
      await pumpEventQueue();

      expect(seen, [null, third]);
      expect(registry().scope!.profileId, third);
    });

    test('marks connections unknown', () async {
      registry().setConnection(world.active(id), const ConnectionOnline());

      await registry().switchTo(away);
      await registry().switchTo(world.home);

      expect(world.active(id).connection, isA<ConnectionUnknown>());
    });

    test('to one that does not exist keeps the old one', () async {
      await expectLater(
        registry().switchTo('nowhere'),
        throwsA(isA<Exception>()),
      );

      expect(registry().scope!.profileId, world.home);
      expect(world.active(id).isCurrent, isTrue);
    });

    test('happens when the active profile is deleted', () async {
      final scope = registry().scope!;
      final context = world.active(id).context;

      await world.profiles.deleteProfile(world.home);
      await registry().refresh();

      expect(scope.isCurrent, isFalse);
      expect(registry().scope!.profileId, away);
      // Its instance is gone: what a module still holds is not stored.
      await context.cache.replace(MediaKind.movie, []);
      expect(await context.cache.read(MediaKind.movie), isNull);
    });
  });

  group('an instance that signs in', () {
    late String away;

    setUp(() async {
      away = await world.profile('Away');
    });

    InstanceDraft draft(String name, Uri url, {bool enabled = true}) =>
        InstanceDraft(
          name: name,
          serviceType: 'client',
          url: url,
          authKind: AuthKind.userPassword,
          enabled: enabled,
        );

    Future<String> addClient(Uri url) async {
      final added = await world.profiles.addInstance(
        world.home,
        draft('Client', url),
        credential: const Credential(username: 'zq-user', password: 'zq-pass'),
      );
      await registry().refresh();
      return (added as Ok<Instance, RuleViolation>).value.id;
    }

    Future<void> save(String id, InstanceDraft changed) async {
      await world.profiles.updateInstance(id, changed);
      await registry().refresh();
    }

    Future<String?> cookie(String id) async =>
        (await world.profiles.credential(id))?.sessionCookie;

    Future<bool> latched(String id) async =>
        (await world.profiles.instance(id))!.authFailed;

    /// Long enough for a request that should not be made to arrive.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 200));

    test('has a way to sign in again', () async {
      final id = await addClient(server.url);

      expect(world.active(id).context.session, isNotNull);
    });

    final retirements = <String, Future<void> Function(String id)>{
      'a switch': (_) => registry().switchTo(away),
      'being disabled': (id) =>
          save(id, draft('Client', server.url, enabled: false)),
      'the registry closing': (_) => registry().close(),
    };
    for (final MapEntry(key: name, value: retire) in retirements.entries) {
      test('sends no read after a sign-in overtaken by $name', () async {
        final id = await addClient(server.url);
        server.hold('login');
        final read = world.active(id).context.http.send(get('a'));
        await server.arrival('login');

        await retire(id);
        expect(await read, failsWith<Unreachable>());
        server.release('login');

        // The sign-in itself finishes.
        await _until(() async => await cookie(id) != null);
        await settle();
        expect(server.calls, ['POST /login']);
      });
    }

    test('does not even sign in for a read given up before that', () async {
      final id = await addClient(server.url);
      final read = world.active(id).context.http.send(get('a'));

      await registry().switchTo(away);

      expect(await read, failsWith<Unreachable>());
      await settle();
      expect(server.calls, isEmpty);
    });

    test('does not sign in again for a read given up', () async {
      final id = await addClient(server.url);
      expect(await world.active(id).context.http.send(get('a')), succeeds);
      server.statuses['expired'] = 403;
      server.hold('expired');
      final read = world.active(id).context.http.send(get('expired'));
      await server.arrival('expired');

      await registry().switchTo(away);
      expect(await read, failsWith<Unreachable>());
      server.release('expired');

      await settle();
      expect(server.calls, ['POST /login', 'GET /a', 'GET /expired']);
    });

    test('still sends a write after the sign-in it waited for', () async {
      final id = await addClient(server.url);
      server.hold('login');
      final http = world.active(id).context.http;
      final read = http.send(get('a'));
      final write = http.send(request(HttpMethod.post, 'command'));
      await server.arrival('login');

      await registry().switchTo(away);
      server.release('login');

      expect(await read, failsWith<Unreachable>());
      expect(await write, succeeds);
      await settle();
      expect(server.calls, ['POST /login', 'POST /command']);
    });

    test('still records a rejection that arrives after a switch', () async {
      final refusing = await GatedServer.start('no');
      final id = await addClient(refusing.url);
      refusing.hold('login');
      final read = world.active(id).context.http.send(get('a'));
      await refusing.arrival('login');

      await registry().switchTo(away);
      expect(await read, failsWith<Unreachable>());
      refusing.release('login');

      await _until(() => latched(id));
      expect(refusing.calls, ['POST /login']);
    });

    test('is not signed in twice at once because of an edit', () async {
      final refusing = await GatedServer.start('no');
      final id = await addClient(refusing.url);
      refusing.hold('login');
      final old = world.active(id).context.http.send(get('a'));
      await refusing.arrival('login');

      await save(id, draft('Renamed', refusing.url));
      final renewed = world.active(id).context.http.send(get('b'));
      expect(await old, failsWith<Unreachable>());
      await settle();
      refusing.release('login');

      expect(await renewed, failsWith<AuthFailed>());
      expect(refusing.calls, ['POST /login']);
    });

    test('rename during a failing sign-in sends one login', () async {
      final id = await addClient(server.url);
      server.statuses['login'] = 500;
      server.hold('login');
      final old = world.active(id).context.http.send(get('a'));
      await server.arrival('login');

      await save(id, draft('Renamed', server.url));
      final renewed = world.active(id).context.http.send(get('b'));
      expect(await old, failsWith<Unreachable>());
      await settle();
      server.release('login');

      expect(await renewed, failsWith<ServerError>());
      // Nor after another rename, or away and back.
      await save(id, draft('Again', server.url));
      await registry().switchTo(away);
      await registry().switchTo(world.home);
      expect(
        await world.active(id).context.http.send(get('c')),
        failsWith<ServerError>(),
      );
      expect(server.calls, ['POST /login']);
    });

    test('signs in again at once when asked after a failure', () async {
      final id = await addClient(server.url);
      server.statuses['login'] = 500;
      expect(
        await world.active(id).context.http.send(get('a')),
        failsWith<ServerError>(),
      );
      server.statuses.remove('login');
      await save(id, draft('Renamed', server.url));

      final signedIn = await world.active(id).context.session!.login();

      expect(signedIn, isA<Ok<void, ServiceFailure>>());
      expect(server.calls, ['POST /login', 'POST /login']);
    });

    test('does not hold up a corrected address with a hung sign-in', () async {
      final corrected = await GatedServer.start();
      final id = await addClient(server.url);
      server.hold('login');
      final old = world.active(id).context.http.send(get('a'));
      await server.arrival('login');

      await save(id, draft('Client', corrected.url));

      // The first sign-in is still unanswered, and would time out after ten
      // seconds.
      final read = world.active(id).context.http.send(get('b'));
      expect(await read.timeout(const Duration(seconds: 5)), succeeds);
      expect(corrected.calls, ['POST /login', 'GET /b']);
      expect(await old, failsWith<Unreachable>());
    });

    test('sends no write to an address saved while it waited', () async {
      final moved = await GatedServer.start();
      final id = await addClient(server.url);
      server.hold('login');
      final old = world.active(id).context.http.send(get('a'));
      await server.arrival('login');
      await save(id, draft('Renamed', server.url));
      final write = world
          .active(id)
          .context
          .http
          .send(request(HttpMethod.post, 'command/7'));
      await settle();

      await save(id, draft('Renamed', moved.url));
      server.release('login');

      expect(await old, failsWith<Unreachable>());
      expect(await write, failsWith<Unreachable>());
      await settle();
      expect(server.calls, ['POST /login']);
      expect(moved.calls, ['POST /login']);
    });

    test('uses the sign-in that an edit overtook', () async {
      final id = await addClient(server.url);
      server.hold('login');
      final old = world.active(id).context.http.send(get('a'));
      await server.arrival('login');

      await save(id, draft('Renamed', server.url));
      final renewed = world.active(id).context.http.send(get('b'));
      expect(await old, failsWith<Unreachable>());
      await settle();
      server.release('login');

      expect(await renewed, succeeds);
      expect(server.calls, ['POST /login', 'GET /b']);
    });
  });

  group('an instance', () {
    test('that is edited gets a new session', () async {
      final id = await world.add('First', server.url);
      final before = world.active(id);
      server.hold('slow');
      final read = before.context.http.send(get('slow'));
      await server.arrival('slow');
      final other = await GatedServer.start();

      await world.edit(id, 'First', other.url);

      expect(await read, failsWith<Unreachable>());
      expect(before.isCurrent, isFalse);
      expect(
        await before.context.http.send(get('a')),
        failsWith<Unreachable>(),
      );
      expect(await world.active(id).context.http.send(get('b')), succeeds);
      expect(other.calls, ['GET /b']);
    });

    test('whose credential alone is edited gets one too', () async {
      final id = await world.add('First', server.url);
      final before = world.active(id);

      await world.edit(
        id,
        'First',
        server.url,
        credential: const Credential(apiKey: 'zq-other-key'),
      );

      expect(before.isCurrent, isFalse);
      expect(world.active(id).isCurrent, isTrue);
    });

    test('that is disabled or removed leaves the scope', () async {
      final first = await world.add('First', server.url);
      final second = await world.add('Second', server.url);
      final disabled = world.active(first);
      final removed = world.active(second);

      await world.edit(first, 'First', server.url, enabled: false);
      await world.profiles.deleteInstance(second);
      await registry().refresh();

      expect(registry().scope!.instances, isEmpty);
      expect(registry().scope!.isCurrent, isTrue);
      for (final gone in [disabled, removed]) {
        expect(gone.isCurrent, isFalse);
        expect(
          await gone.context.http.send(get('a')),
          failsWith<Unreachable>(),
        );
      }
      await removed.context.cache.replace(MediaKind.movie, []);
      expect(server.calls, isEmpty);
    });

    test('keeps its connection state until it is edited', () async {
      final id = await world.add('First', server.url);
      final before = world.active(id);

      registry().setConnection(before, const ConnectionOffline(Unreachable()));
      expect(world.active(id).connection, isA<ConnectionOffline>());
      await world.profiles.markAuthFailed(id);
      await registry().refresh();
      expect(world.active(id).connection, isA<ConnectionOffline>());

      registry().resetConnections();
      expect(world.active(id).connection, isA<ConnectionUnknown>());

      await world.edit(id, 'Renamed', server.url);
      // A late answer for what was there before.
      registry().setConnection(before, const ConnectionOnline());
      expect(world.active(id).connection, isA<ConnectionUnknown>());
    });
  });

  group('artwork', () {
    late GatedServer pictures;

    setUp(() async {
      pictures = await GatedServer.start();
    });

    test('of the instance is loaded with its session', () async {
      final server = await pictureServer(twoPixels);
      final id = await world.add('First', server.url());

      final width = await widthOf(
        world.active(id).context.artwork.image(instanceImage('a')),
      );

      expect(width, 2);
      expect(server.requests.single.headers['x-api-key'], apiKey);
    });

    test('is cleared when the address changes, not otherwise', () async {
      final server = await pictureServer(onePixel);
      final id = await world.add('First', server.url());
      await widthOf(world.active(id).context.artwork.image(instanceImage('a')));

      await world.edit(id, 'Renamed', server.url());
      await pumpEventQueue();
      expect(filesIn(world.directory), isNotEmpty);

      await world.edit(id, 'Renamed', pictures.url);
      await _until(() => filesIn(world.directory).isEmpty);
    });

    test('is cleared when an instance of any profile is removed', () async {
      final away = await world.profile('Away');
      final server = await pictureServer(onePixel);
      final id = await world.add('First', server.url());
      await widthOf(world.active(id).context.artwork.image(instanceImage('a')));
      await registry().switchTo(away);

      await world.profiles.deleteInstance(id);
      await registry().refresh();

      await _until(() => filesIn(world.directory).isEmpty);
    });
  });
}

/// Waits for something that happens after the registry has answered.
Future<void> _until(FutureOr<bool> Function() done) async {
  final waited = Stopwatch()..start();
  while (!await done()) {
    if (waited.elapsed > const Duration(seconds: 10)) fail('never happened');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
