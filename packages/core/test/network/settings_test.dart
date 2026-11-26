/// The client of a saved instance. A credential goes only to the address it was
/// saved with (constitution III, FR-070), also while it is being edited. The
/// instance and its credential are stored apart, so reading them one after the
/// other can pair a new credential with an old address or the reverse. The API
/// is described in client_test.dart. The two tests of saved certificate trust
/// need T024.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';

import 'certificates.dart';
import 'support.dart';

class _Module implements ServiceModule {
  @override
  String get id => 'radarr';

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
    displayName: 'Radarr',
    icon: IconData(0),
    category: ModuleCategory.movies,
    authKinds: [AuthKind.apiKey],
    apiKeyHeader: apiKeyHeader,
    defaultPort: 7878,
    minimumVersion: '1',
    testedVersion: '1',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Can hold up one read, to let a change happen in the middle of a send.
class _SecretStore implements SecretStore {
  final values = <String, String>{};
  Completer<void>? _held;
  final _release = Completer<void>();
  var _readBeforeHolding = false;

  /// Holds up the next read until [release]. It returns what was stored when it
  /// began if [readBeforeHolding], else what is stored when released. The
  /// future completes when that read has begun.
  Future<void> holdNextRead({required bool readBeforeHolding}) {
    _readBeforeHolding = readBeforeHolding;
    return (_held = Completer<void>()).future;
  }

  void release() => _release.complete();

  @override
  Future<String?> read(String key) async {
    final held = _held;
    if (held == null) return values[key];
    _held = null;
    final before = values[key];
    held.complete();
    await _release.future;
    return _readBeforeHolding ? before : values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

const _oldKey = 'zq-old-key-111';
const _newKey = 'zq-new-key-222';

InstanceDraft _draft(Uri url, {String? certPin, String? customCa}) =>
    InstanceDraft(
      name: 'Movies',
      serviceType: 'radarr',
      url: url,
      authKind: AuthKind.apiKey,
      acceptedCertPin: certPin,
      customCa: customCa,
    );

void main() {
  late AppDatabase database;
  late _SecretStore secrets;
  late ProfileRepository repository;
  late String profileId;
  late TestServer oldServer;
  late TestServer newServer;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    secrets = _SecretStore();
    repository = ProfileRepository(
      database: database,
      secrets: secrets,
      log: DiagnosticLog(),
      preferences: PreferencesRepository(database),
      modules: [_Module()],
    );
    await repository.ensureDefaultProfile();
    profileId = (await repository.profiles()).single.id;
    oldServer = await TestServer.start();
    newServer = await TestServer.start();
  });
  tearDown(() => database.close());

  Future<Instance> add(
    InstanceDraft draft, {
    Credential credential = const Credential(apiKey: _oldKey),
  }) async => switch (await repository.addInstance(
    profileId,
    draft,
    credential: credential,
  )) {
    Ok(:final value) => value,
    Err(:final error) => fail('refused: $error'),
  };

  /// Moves the instance to the new server with the new key.
  Future<void> move(String id) async {
    final result = await repository.updateInstance(
      id,
      _draft(newServer.url()),
      credential: const Credential(apiKey: _newKey),
    );
    expect(result, isA<Ok<Instance, RuleViolation>>());
  }

  InstanceHttpClient clientOf(String id) {
    final client = InstanceHttpClient.saved(
      profiles: repository,
      instanceId: id,
      apiKeyHeader: apiKeyHeader,
      log: DiagnosticLog(),
      localNetwork: FakePermission(),
    );
    addTearDown(client.close);
    return client;
  }

  List<String?> keys(TestServer server) => [
    for (final received in server.requests) received.headers['x-api-key'],
  ];

  test('sends no key where none is stored', () async {
    final instance = await add(
      _draft(oldServer.url()),
      credential: const Credential(),
    );

    expectOk(await clientOf(instance.id).send(get()));

    expect(keys(oldServer), [null]);
  });

  for (final (name, certificate, pin, authority) in [
    (
      'pin',
      TestCertificate.selfSigned,
      TestCertificate.selfSigned.sha256,
      null,
    ),
    ('authority', TestCertificate.leaf, null, TestCertificate.ca),
  ]) {
    test('uses the saved certificate $name', () async {
      final server = await TlsServer.start(certificate.serverContext());
      final instance = await add(
        _draft(server.url(), certPin: pin, customCa: authority?.pem),
      );

      expectOk(await clientOf(instance.id).send(get()));

      expect(server.received, contains(_oldKey));
    });
  }

  test('a client follows an edit with its next request', () async {
    final instance = await add(_draft(oldServer.url()));
    final client = clientOf(instance.id);
    expectOk(await client.send(get()));

    await move(instance.id);
    expectOk(await client.send(get()));

    expect(keys(oldServer), [_oldKey]);
    expect(keys(newServer), [_newKey]);
  });

  test('a client of a deleted instance sends nothing', () async {
    final instance = await add(_draft(oldServer.url()));
    final client = clientOf(instance.id);

    await repository.deleteInstance(instance.id);
    expectError(await client.send(get()));

    expect(oldServer.requests, isEmpty);
  });

  for (final readBeforeHolding in [true, false]) {
    final secretRead = readBeforeHolding ? 'an early' : 'a late';
    test('an edit during a send never mixes address and credential, with '
        '$secretRead secret read', () async {
      final instance = await add(_draft(oldServer.url()));
      final client = clientOf(instance.id);

      final held = secrets.holdNextRead(readBeforeHolding: readBeforeHolding);
      final sending = client.send(get());
      await held;
      // The edit may have to wait for the read, so it is not awaited yet.
      final editing = move(instance.id);
      await Future.any([editing, pause()]);
      secrets.release();
      await editing;
      // Reaching either server is acceptable, and so is giving up.
      await sending;
      await pause();

      expect(keys(oldServer), everyElement(_oldKey));
      expect(keys(newServer), everyElement(_newKey));

      expectOk(await client.send(get()));
      expect(keys(newServer).last, _newKey);
      expect(keys(oldServer), everyElement(_oldKey));
    });
  }
}
