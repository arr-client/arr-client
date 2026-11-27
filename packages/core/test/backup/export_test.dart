/// What an export holds (contracts/backup-format.md).
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../network/support.dart'
    show credential, secretValues, sessionCookie, apiKey;
import 'support.dart';

/// Every key of every object in [json].
Set<String> _keys(Object? json) => switch (json) {
  final Map<String, Object?> map => {
    ...map.keys,
    for (final value in map.values) ..._keys(value),
  },
  final List<Object?> list => {for (final value in list) ..._keys(value)},
  _ => {},
};

const _envelopeKeys = {
  'format',
  'version',
  'createdAt',
  'encrypted',
  'payload',
};

const _instanceKeys = {
  'id',
  'profileId',
  'name',
  'serviceType',
  'url',
  'authKind',
  'certPin',
  'customCa',
  'enabled',
  'sortOrder',
  'links',
  'createdAt',
  'updatedAt',
};

void main() {
  final ca = File('test/network/certs/ca.pem').readAsStringSync();

  late Device device;
  late String away;
  late Instance movies;
  late Instance subtitles;

  setUp(() async {
    device = await Device.fresh();
    away = await device.profile('Away');
    movies = await device.add(
      'Movies',
      credential: Credential(
        apiKey: credential.apiKey,
        username: credential.username,
        password: credential.password,
        basicUser: credential.basicUser,
        basicPassword: credential.basicPassword,
        customHeaders: credential.customHeaders,
      ),
      certPin: pin,
      customCa: ca,
    );
    await device.signIn(movies.id, sessionCookie);
    subtitles = await device.add(
      'Subtitles',
      serviceType: 'bazarr',
      url: 'https://nas.test/bazarr',
      links: [
        InstanceLink(
          type: InstanceLinkType.subtitlesFor,
          instanceId: movies.id,
        ),
      ],
    );
    await device.add('Elsewhere', profileId: away, serviceType: 'sonarr');
    // What must not leave the device.
    final used = (await device.profiles.instanceWithCredential(movies.id))!;
    await device.profiles.recordProbe(
      used,
      const ProbeSnapshot(
        product: 'zq-product',
        version: 'zq-version',
        capabilities: {CapabilityKind.health},
      ),
    );
    await device.profiles.recordUnsupportedVersion(used, 'zq-old-version');
    await device.profiles.markAuthFailed(movies.id);
    await device.mark(movies.id, 'zq-cursor');
    await device.subscribe(movies.id, 'imported');
    await device.subscribe(movies.id, 'healthIssue', enabled: false);
    await device.preferences.setAppLock(
      const AppLock(enabled: true, delaySeconds: 30),
    );
    await device.preferences.setThemeMode(AppThemeMode.dark);
  });

  /// What must hold of the payload, plain or decrypted.
  void expectSchema(Map<String, Object?> body) {
    expect(body.keys, {
      'profiles',
      'instances',
      'preferences',
      'subscriptions',
    });

    final profiles = records(body['profiles']);
    expect(profiles.map((profile) => profile['name']), ['Default', 'Away']);
    for (final profile in profiles) {
      expect(profile.keys, unorderedEquals(['id', 'name', 'sortOrder']));
    }

    final instances = records(body['instances']);
    expect(instances, hasLength(3));
    final first = instances.singleWhere((i) => i['id'] == movies.id);
    expect(first['profileId'], device.home);
    expect(first['name'], 'Movies');
    expect(first['serviceType'], 'radarr');
    expect(first['url'], 'http://nas.test:7878/radarr');
    expect(first['authKind'], 'apiKey');
    expect(first['certPin'], pin);
    expect(first['customCa'], ca);
    expect(first['enabled'], true);
    final linked = instances.singleWhere((i) => i['id'] == subtitles.id);
    expect(records(linked['links']), [
      {'type': 'subtitlesFor', 'instanceId': movies.id},
    ]);
    for (final instance in instances) {
      expect(
        instance.keys.toSet().difference({..._instanceKeys, 'credential'}),
        isEmpty,
      );
    }

    final preferences = body['preferences']! as Map<String, Object?>;
    expect(preferences['themeMode'], 'dark');
    expect(preferences['trueBlack'], false);
    expect(preferences['dynamicColor'], true);
    expect(preferences['loadThirdPartyArtwork'], true);
    expect(
      preferences.keys.toSet().difference({
        ...defaultPreferences.keys,
        'view',
        'lastAddChoices',
      }),
      isEmpty,
    );

    expect(
      records(body['subscriptions']),
      unorderedEquals([
        {'instanceId': movies.id, 'eventType': 'imported', 'enabled': true},
        {'instanceId': movies.id, 'eventType': 'healthIssue', 'enabled': false},
      ]),
    );

    final text = jsonEncode(body);
    for (final absent in [
      'zq-product',
      'zq-version',
      'zq-old-version',
      'zq-cursor',
      'zq-delta-444',
    ]) {
      expect(text, isNot(contains(absent)));
    }
    expect(
      _keys(body).intersection({
        'lastProbe',
        'detectedVersion',
        'unsupportedVersion',
        'authFailed',
        'appLock',
        'activeProfileId',
        'sessionCookie',
        'openKeys',
        'lastSeenCursor',
        'requestSnapshot',
      }),
      isEmpty,
    );
  }

  group('without credentials', () {
    test('is a version 1 setup export with the payload schema', () async {
      final json = jsonOf(await device.export());

      expect(json.keys, unorderedEquals(_envelopeKeys));
      expect(json['format'], 'arr-client-setup');
      expect(json['version'], 1);
      expect(json['encrypted'], false);
      final createdAt = json['createdAt']! as String;
      expect(createdAt, endsWith('Z'));
      expect(DateTime.parse(createdAt), DateTime.parse(exportTime));
      expectSchema(json['payload']! as Map<String, Object?>);
    });

    test('holds no secret, credential field, header or cookie', () async {
      final file = await device.export();
      final text = utf8.decode(file);

      for (final secret in [...secretValues, 'X-Proxy-Id']) {
        expect(text, isNot(contains(secret)));
      }
      expect(
        _keys(jsonOf(file)).intersection({
          'credential',
          'apiKey',
          'username',
          'password',
          'basicUser',
          'basicPassword',
          'customHeaders',
          'sessionCookie',
        }),
        isEmpty,
      );
    });

    test('does not need the secret store', () async {
      device.secrets.failReads = true;

      expect(jsonOf(await device.export())['encrypted'], false);
    });
  });

  group('with credentials', () {
    test('is encrypted with the stated parameters', () async {
      final file = await device.export(passphrase);
      final json = jsonOf(file);

      expect(json.keys, unorderedEquals(_envelopeKeys));
      expect(json['encrypted'], true);
      final body = json['payload']! as Map<String, Object?>;
      expect(body.keys, unorderedEquals(['kdf', 'cipher', 'nonce', 'data']));
      expect(body['cipher'], 'aes-256-gcm');
      final kdf = body['kdf']! as Map<String, Object?>;
      expect(kdf, {
        'name': 'argon2id',
        'salt': isA<String>(),
        'memoryKiB': 65536,
        'iterations': 3,
        'parallelism': 1,
      });
      expect(base64.decode(kdf['salt']! as String), hasLength(16));
      expect(base64.decode(body['nonce']! as String), hasLength(12));
      final text = utf8.decode(file);
      for (final hidden in [
        ...secretValues,
        passphrase,
        'nas.test',
        'Movies',
      ]) {
        expect(text, isNot(contains(hidden)));
      }
    });

    test('opens with the passphrase to the payload schema', () async {
      final body = await decrypt(await device.export(passphrase));

      expectSchema(body);
      final instances = records(body['instances']);
      expect(instances.singleWhere((i) => i['id'] == movies.id)['credential'], {
        'apiKey': apiKey,
        'username': credential.username,
        'password': credential.password,
        'basicUser': credential.basicUser,
        'basicPassword': credential.basicPassword,
        'customHeaders': credential.customHeaders,
      });
      // One without a credential has none, or an empty one.
      expect(
        instances.singleWhere((i) => i['id'] == subtitles.id)['credential'],
        anyOf(isNull, isEmpty),
      );
    });

    test('uses a new salt and nonce each time', () async {
      Future<Map<String, Object?>> body() async =>
          jsonOf(await device.export(passphrase))['payload']!
              as Map<String, Object?>;
      final first = await body();
      final second = await body();

      expect(second['nonce'], isNot(first['nonce']));
      expect(
        (second['kdf']! as Map)['salt'],
        isNot((first['kdf']! as Map)['salt']),
      );
      expect(second['data'], isNot(first['data']));
    });

    test('fails rather than leave credentials out', () async {
      device.secrets.failReads = true;

      await expectLater(
        device.backup.export(passphrase: passphrase),
        throwsStateError,
      );
    });

    test('keeps the passphrase and secrets out of the log', () async {
      await device.export(passphrase);
      device.log.log(LogLevel.info, 'marker');

      final text = device.log.entries.join('\n');
      for (final secret in [...secretValues, passphrase]) {
        expect(text, isNot(contains(secret)));
      }
    });
  });

  group('the passphrase', () {
    for (final (name, short) in [
      ('empty', ''),
      ('of 9 characters', 'abcdefghi'),
      // Ten UTF-16 code units are not ten characters.
      ('of 5 emoji', '\u{1F511}' * 5),
    ]) {
      test('is refused when $name', () async {
        expect(
          await device.backup.export(passphrase: short),
          isA<Err<Object?, BackupProblem>>().having(
            (result) => result.error,
            'error',
            BackupProblem.passphraseTooShort,
          ),
        );
      });
    }

    test('may have 10 characters, not only ASCII ones', () async {
      const phrase = 'pässwörd 1';
      final file = await device.export(phrase);

      expect((await decrypt(file, phrase))['instances'], hasLength(3));
    });
  });

  test('is never a file that an import would refuse as too large', () async {
    // Each authority is just under its own limit of 64 KiB.
    final large = ca * (60 * 1024 ~/ ca.length);
    for (var i = 0; i < 20; i++) {
      await device.add('Large $i', customCa: large);
    }

    switch (await device.backup.export()) {
      case Ok(:final value):
        expect(value.length, lessThanOrEqualTo(maximumFileBytes));
        expect(await device.refusal(value), isNull);
      case Err(:final error):
        expect(error, BackupProblem.tooLarge);
    }
  });
}
