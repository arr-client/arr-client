/// Devices to export from and import into, and setup files written by hand.
///
/// The files are built and opened with `package:cryptography` directly, so
/// that the app's code is not its own judge, with the choices that
/// contracts/backup-format.md states. `golden_v1.arrclient.json` was written
/// by `golden_v1.py`, with argon2-cffi and Python's cryptography, not with the
/// packages used here.
library;

import 'dart:convert';

import 'package:core/core.dart';
// To seed and inspect rows that other repositories own.
import 'package:core/src/storage/database.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';

const passphrase = 'zq passphrase 888';
const associatedData = 'arr-client-setup:1';
const exportTime = '2026-11-26T00:00:00Z';
const maximumFileBytes = 1024 * 1024;

/// A certificate fingerprint as the app stores one.
final pin = 'ab' * 32;
final otherPin = 'cd' * 32;

class _Module implements ServiceModule {
  _Module(this.id, ModuleCategory category, {String header = 'X-Api-Key'})
    : descriptor = ModuleDescriptor(
        displayName: id,
        icon: const IconData(0),
        category: category,
        authKinds: const [AuthKind.apiKey, AuthKind.userPassword],
        apiKeyHeader: ApiKeyHeader(header),
        defaultPort: 80,
        minimumVersion: '1',
        testedVersion: '1',
      );

  @override
  final String id;

  @override
  final ModuleDescriptor descriptor;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `bearer` sends its API key in `Authorization`, so it excludes basic auth.
final modules = <ServiceModule>[
  _Module('radarr', ModuleCategory.movies),
  _Module('sonarr', ModuleCategory.series),
  _Module('bazarr', ModuleCategory.subtitles),
  _Module('bearer', ModuleCategory.movies, header: 'Authorization'),
];

/// Secure storage in memory that can be made to fail.
class Secrets implements SecretStore {
  final values = <String, String>{};

  var failReads = false;
  var failDeletes = false;
  bool Function(String key) failWrite = (_) => false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('read');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite(key)) throw StateError('write');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('delete');
    values.remove(key);
  }
}

T ok<T, E>(Result<T, E> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw TestFailure('Refused: $error'),
};

/// One installation of the app.
class Device {
  Device._();

  final database = AppDatabase(NativeDatabase.memory());
  final secrets = Secrets();
  final log = DiagnosticLog();
  late final preferences = PreferencesRepository(database);
  late final profiles = ProfileRepository(
    database: database,
    secrets: secrets,
    log: log,
    preferences: preferences,
    modules: modules,
  );
  late final backup = SetupBackup(
    database: database,
    secrets: secrets,
    log: log,
    preferences: preferences,
    profiles: profiles,
    modules: modules,
    now: () => DateTime.parse(exportTime),
  );

  /// The profile made at first launch, "Default".
  late final String home;

  /// As after the first launch.
  static Future<Device> fresh() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final device = Device._();
    addTearDown(device.database.close);
    await device.profiles.ensureDefaultProfile();
    device.home = (await device.profiles.profiles()).single.id;
    return device;
  }

  Future<String> profile(String name) async =>
      ok(await profiles.createProfile(name)).id;

  Future<Instance> add(
    String name, {
    String? profileId,
    String url = 'http://nas.test:7878/radarr',
    String serviceType = 'radarr',
    AuthKind authKind = AuthKind.apiKey,
    Credential credential = const Credential(),
    String? certPin,
    String? customCa,
    List<InstanceLink> links = const [],
  }) async => ok(
    await profiles.addInstance(
      profileId ?? home,
      InstanceDraft(
        name: name,
        serviceType: serviceType,
        url: Uri.parse(url),
        authKind: authKind,
        acceptedCertPin: certPin,
        customCa: customCa,
        links: links,
      ),
      credential: credential,
    ),
  );

  Future<void> signIn(String id, String cookie) async {
    final used = (await profiles.instanceWithCredential(id))!;
    expect(await profiles.saveSession(used, cookie), isTrue);
  }

  Future<void> subscribe(String id, String eventType, {bool enabled = true}) =>
      database
          .into(database.notificationSubscriptions)
          .insertOnConflictUpdate(
            NotificationSubscriptionsCompanion.insert(
              instanceId: id,
              eventType: eventType,
              enabled: Value(enabled),
            ),
          );

  Future<Set<(String, String, bool)>> subscriptions() async => {
    for (final row
        in await database.select(database.notificationSubscriptions).get())
      (row.instanceId, row.eventType, row.enabled),
  };

  Future<void> mark(String id, String cursor) => database
      .into(database.eventMarkers)
      .insert(
        EventMarkersCompanion.insert(
          instanceId: id,
          eventType: 'imported',
          lastSeenCursor: Value(cursor),
        ),
      );

  Future<Set<String>> marked() async => {
    for (final row in await database.select(database.eventMarkers).get())
      row.instanceId,
  };

  Future<List<String>> profileNames() async => [
    for (final profile in await profiles.profiles()) profile.name,
  ];

  Future<String?> activeProfile() async =>
      (await preferences.read()).activeProfileId;

  Future<List<int>> export([String? passphrase]) async =>
      ok(await backup.export(passphrase: passphrase));

  Future<ImportPreview> preview(List<int> file, [String? passphrase]) async =>
      ok(
        await backup.preview(
          ok(await backup.read(file, passphrase: passphrase)),
        ),
      );

  /// Reads, previews and confirms.
  Future<ImportPreview> import(List<int> file, [String? passphrase]) async {
    final shown = await preview(file, passphrase);
    ok(await backup.apply(shown));
    return shown;
  }

  /// Why [file] cannot be imported, whether reading or previewing it says so.
  /// Null if neither does.
  Future<BackupProblem?> refusal(List<int> file, [String? passphrase]) async {
    switch (await backup.read(file, passphrase: passphrase)) {
      case Err(:final error):
        return error;
      case Ok(:final value):
        return switch (await backup.preview(value)) {
          Err(:final error) => error,
          Ok() => null,
        };
    }
  }

  /// Everything saved, to tell that nothing changed.
  Future<String> snapshot() async {
    final text = StringBuffer();
    for (final table in database.allTables) {
      final rows = await database.select(table).get();
      final lines = [for (final row in rows) '$row']..sort();
      text.writeln('${table.actualTableName}: ${lines.join('; ')}');
    }
    for (final key in secrets.values.keys.toList()..sort()) {
      text.writeln('$key=${secrets.values[key]}');
    }
    return text.toString();
  }
}

// Setup files by hand.

String uuid(int n) => '00000000-0000-4000-8000-${'$n'.padLeft(12, '0')}';

Map<String, Object?> profileJson(int id, String name, {int? sortOrder}) => {
  'id': uuid(id),
  'name': name,
  'sortOrder': sortOrder ?? id,
};

Map<String, Object?> instanceJson(
  int id,
  String name, {
  required int profile,
  String url = 'http://nas.test:7878/radarr',
  String serviceType = 'radarr',
  String authKind = 'apiKey',
  Map<String, Object?>? credential,
  String? certPin,
  String? customCa,
  List<Map<String, Object?>> links = const [],
}) => {
  'id': uuid(id),
  'profileId': uuid(profile),
  'name': name,
  'serviceType': serviceType,
  'url': url,
  'authKind': authKind,
  'certPin': ?certPin,
  'customCa': ?customCa,
  'enabled': true,
  'sortOrder': id,
  'links': links,
  'createdAt': '2026-01-02T00:00:00.000Z',
  'updatedAt': '2026-01-02T00:00:00.000Z',
  'credential': ?credential,
};

/// The preferences of a new installation.
const defaultPreferences = <String, Object?>{
  'themeMode': 'system',
  'trueBlack': false,
  'dynamicColor': true,
  'loadThirdPartyArtwork': true,
};

Map<String, Object?> payload({
  List<Map<String, Object?>> profiles = const [],
  List<Map<String, Object?>> instances = const [],
  Map<String, Object?> preferences = defaultPreferences,
  List<Map<String, Object?>> subscriptions = const [],
}) => {
  'profiles': profiles,
  'instances': instances,
  'preferences': preferences,
  'subscriptions': subscriptions,
};

Map<String, Object?> envelope(
  Object? payload, {
  required bool encrypted,
  Object? format = 'arr-client-setup',
  Object? version = 1,
}) => {
  'format': format,
  'version': version,
  'createdAt': exportTime,
  'encrypted': encrypted,
  'payload': payload,
};

List<int> bytesOf(Object? json) => utf8.encode(jsonEncode(json));

Map<String, Object?> jsonOf(List<int> file) =>
    jsonDecode(utf8.decode(file)) as Map<String, Object?>;

/// A file without credentials.
List<int> plainFile(Map<String, Object?> payload) =>
    bytesOf(envelope(payload, encrypted: false));

Future<SecretKey> _key(
  String passphrase,
  List<int> salt, {
  required int memoryKiB,
  required int iterations,
}) => Argon2id(
  memory: memoryKiB,
  iterations: iterations,
  parallelism: 1,
  hashLength: 32,
).deriveKeyFromPassword(password: passphrase, nonce: salt);

/// An encrypted file of [payload]. The key derivation is cheap unless asked, as
/// the contract sets only upper limits.
Future<List<int>> encryptedFile(
  Object? payload, {
  String phrase = passphrase,
  int memoryKiB = 64,
  int iterations = 1,
  int saltLength = 16,
  int nonceLength = 12,
  String aad = associatedData,
}) async {
  final salt = List.generate(saltLength, (i) => i + 1);
  final nonce = List.generate(nonceLength, (i) => i + 40);
  final box = await AesGcm.with256bits(nonceLength: nonceLength).encrypt(
    utf8.encode(jsonEncode(payload)),
    secretKey: await _key(
      phrase,
      salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
    ),
    nonce: nonce,
    aad: utf8.encode(aad),
  );
  return bytesOf(
    envelope({
      'kdf': {
        'name': 'argon2id',
        'salt': base64.encode(salt),
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': 1,
      },
      'cipher': 'aes-256-gcm',
      'nonce': base64.encode(nonce),
      'data': base64.encode([...box.cipherText, ...box.mac.bytes]),
    }, encrypted: true),
  );
}

/// The payload of an encrypted file, opened as the contract says.
Future<Map<String, Object?>> decrypt(
  List<int> file, [
  String phrase = passphrase,
]) async {
  final body = jsonOf(file)['payload']! as Map<String, Object?>;
  final kdf = body['kdf']! as Map<String, Object?>;
  final data = base64.decode(body['data']! as String);
  final clear = await AesGcm.with256bits().decrypt(
    SecretBox(
      data.sublist(0, data.length - 16),
      nonce: base64.decode(body['nonce']! as String),
      mac: Mac(data.sublist(data.length - 16)),
    ),
    secretKey: await _key(
      phrase,
      base64.decode(kdf['salt']! as String),
      memoryKiB: kdf['memoryKiB']! as int,
      iterations: kdf['iterations']! as int,
    ),
    aad: utf8.encode(associatedData),
  );
  return jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
}

List<Map<String, Object?>> records(Object? list) =>
    (list! as List<Object?>).cast<Map<String, Object?>>();
