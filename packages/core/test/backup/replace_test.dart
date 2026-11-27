/// The cases the task of T152 did not decide, each as
/// contracts/backup-format.md now states it.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:core/src/storage/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _elsewhere = 'http://other.test:7878/radarr';
const _credential = Credential(apiKey: 'zq-old-key');

void main() {
  final ca = File('test/network/certs/ca.pem').readAsStringSync();

  late Device device;

  setUp(() async => device = await Device.fresh());

  Map<String, Object?> homeProfile() => {
    'id': device.home,
    'name': 'Default',
    'sortOrder': 0,
  };

  /// [local] as a file would replace it.
  Map<String, Object?> replacing(
    Instance local, {
    String? name,
    String? url,
    String? authKind,
    String? certPin,
    String? customCa,
    Map<String, Object?>? credential,
  }) => {
    ...instanceJson(
      2,
      name ?? local.name,
      profile: 1,
      url: url ?? '${local.url}',
      serviceType: local.serviceType,
      authKind: authKind ?? local.authKind.name,
      certPin: certPin,
      customCa: customCa,
      credential: credential,
    ),
    'id': local.id,
    'profileId': local.profileId,
  };

  Map<String, Object?> bodyOf(
    List<Map<String, Object?>> instances, {
    List<Map<String, Object?>> subscriptions = const [],
  }) => payload(
    profiles: [homeProfile()],
    instances: instances,
    subscriptions: subscriptions,
  );

  Future<void> importPlain(List<Map<String, Object?>> instances) =>
      device.import(plainFile(bodyOf(instances)));

  Future<void> importSealed(List<Map<String, Object?>> instances) async =>
      device.import(await encryptedFile(bodyOf(instances)), passphrase);

  Future<Instance> saved(String id) async =>
      (await device.profiles.instance(id))!;

  group('at the same origin', () {
    test('a file without a pin keeps the stored one', () async {
      final local = await device.add('Movies', certPin: pin);

      await importPlain([replacing(local)]);

      expect((await saved(local.id)).certPin, pin);
    });

    test('a file with a pin replaces the stored one', () async {
      final local = await device.add('Movies', certPin: pin);

      await importPlain([replacing(local, certPin: otherPin)]);

      expect((await saved(local.id)).certPin, otherPin);
    });

    test('a file without an authority removes the stored one', () async {
      final local = await device.add('Movies', customCa: ca);

      await importPlain([replacing(local)]);

      expect((await saved(local.id)).customCa, isNull);
    });

    test('an empty credential keeps the secrets', () async {
      final local = await device.add('Movies', credential: _credential);

      await importSealed([replacing(local, credential: {})]);

      expect(
        (await device.profiles.credential(local.id))!.apiKey,
        'zq-old-key',
      );
    });

    test('the same credential keeps the session and the latch', () async {
      final local = await device.add('Movies', credential: _credential);
      await device.signIn(local.id, 'SID=zq-session');
      await device.profiles.markAuthFailed(local.id);

      await importSealed([
        replacing(local, credential: {'apiKey': 'zq-old-key'}),
      ]);

      expect((await saved(local.id)).authFailed, isTrue);
      expect(
        (await device.profiles.credential(local.id))!.sessionCookie,
        'SID=zq-session',
      );
    });
  });

  group('at another origin', () {
    test('the same credential keeps the latch but not the session', () async {
      final local = await device.add('Movies', credential: _credential);
      await device.signIn(local.id, 'SID=zq-session');
      await device.profiles.markAuthFailed(local.id);

      await importSealed([
        replacing(local, url: _elsewhere, credential: {'apiKey': 'zq-old-key'}),
      ]);

      expect((await saved(local.id)).authFailed, isTrue);
      expect((await device.profiles.credential(local.id))!.sessionCookie, null);
    });

    test('dropping the secrets keeps the latch', () async {
      final local = await device.add('Movies', credential: _credential);
      await device.profiles.markAuthFailed(local.id);

      await importPlain([replacing(local, url: _elsewhere)]);

      expect((await saved(local.id)).authFailed, isTrue);
      expect(device.secrets.values, isEmpty);
    });

    test('secrets dropped are put back if another write fails', () async {
      final local = await device.add('Movies', credential: _credential);
      final preview = await device.preview(
        await encryptedFile(
          bodyOf([
            replacing(local, url: _elsewhere),
            {
              ...instanceJson(
                3,
                'Second',
                profile: 1,
                credential: {'apiKey': 'zq-second'},
              ),
              'profileId': device.home,
            },
          ]),
        ),
        passphrase,
      );
      final before = await device.snapshot();
      device.secrets.failWrite = (key) => key == 'cred/${uuid(3)}';

      await expectLater(device.backup.apply(preview), throwsStateError);

      expect(await device.snapshot(), before);
    });
  });

  // As when erasing the secret of a deleted instance failed.
  group('a new instance whose id has a secret left behind', () {
    List<Map<String, Object?>> added([Map<String, Object?>? credential]) => [
      {
        ...instanceJson(
          2,
          'Movies',
          profile: 1,
          url: _elsewhere,
          credential: credential,
        ),
        'profileId': device.home,
      },
    ];

    setUp(
      () => device.secrets.values['cred/${uuid(2)}'] = '{"apiKey":"zq-left"}',
    );

    test('is not given it', () async {
      await importPlain(added());

      expect(device.secrets.values, isEmpty);
    });

    test('has only what the file carries', () async {
      await importSealed(added({'username': 'zq-new'}));

      final stored = (await device.profiles.credential(uuid(2)))!;
      expect(stored.username, 'zq-new');
      expect(stored.apiKey, isNull);
    });

    test('is not added if the secret cannot be erased', () async {
      final preview = await device.preview(plainFile(bodyOf(added())));
      device.secrets.failDeletes = true;

      await expectLater(device.backup.apply(preview), throwsStateError);

      expect(await device.profiles.instance(uuid(2)), isNull);
    });
  });

  group('basic auth and an API key in the same header', () {
    late Instance local;

    setUp(
      () async => local = await device.add(
        'Bearer',
        serviceType: 'bearer',
        authKind: AuthKind.userPassword,
        credential: const Credential(basicUser: 'u', basicPassword: 'p'),
      ),
    );

    test('refuses a change to an API key that would keep both', () async {
      final before = await device.snapshot();

      expect(
        await device.refusal(
          plainFile(bodyOf([replacing(local, authKind: 'apiKey')])),
        ),
        BackupProblem.invalidContent,
      );
      expect(await device.snapshot(), before);
    });

    test('allows it where the basic auth is dropped anyway', () async {
      await importPlain([
        replacing(local, authKind: 'apiKey', url: _elsewhere),
      ]);

      expect(device.secrets.values, isEmpty);
    });

    test('allows it with a credential of the file', () async {
      await importSealed([
        replacing(local, authKind: 'apiKey', credential: {'apiKey': 'zq-new'}),
      ]);

      expect((await device.profiles.credential(local.id))!.basicUser, isNull);
    });
  });

  test('local subscriptions the file does not list are removed', () async {
    final local = await device.add('Movies');
    await device.subscribe(local.id, 'imported');
    await device.subscribe(local.id, 'healthIssue');

    await device.import(
      plainFile(
        bodyOf(
          [replacing(local)],
          subscriptions: [
            {
              'instanceId': local.id,
              'eventType': 'healthIssue',
              'enabled': false,
            },
          ],
        ),
      ),
    );

    expect(await device.subscriptions(), {(local.id, 'healthIssue', false)});
  });

  test('an instance cannot move to another profile', () async {
    final local = await device.add('Movies');
    final before = await device.snapshot();
    final file = plainFile(
      payload(
        profiles: [profileJson(1, 'Restored')],
        instances: [
          {...replacing(local), 'profileId': uuid(1)},
        ],
      ),
    );

    expect(await device.refusal(file), BackupProblem.invalidContent);
    expect(await device.snapshot(), before);
  });

  group('names', () {
    test('two replaced records may swap them', () async {
      final one = await device.add('One');
      final two = await device.add('Two');

      await importPlain([
        replacing(one, name: 'Two'),
        replacing(two, name: 'One'),
      ]);

      expect((await saved(one.id)).name, 'Two');
      expect((await saved(two.id)).name, 'One');
    });

    test('a record that keeps its name has the first claim to it', () async {
      final one = await device.add('One');
      final two = await device.add('Two');

      await importPlain([
        {...instanceJson(3, 'two', profile: 1), 'profileId': device.home},
        replacing(one, name: 'Two'),
        replacing(two),
      ]);

      expect((await saved(two.id)).name, 'Two');
      expect((await saved(one.id)).name, 'Two (2)');
      expect((await saved(uuid(3))).name, 'two (3)');
    });
  });

  group('preferences', () {
    test('that the file does not name stay', () async {
      await device.preferences.setThemeMode(AppThemeMode.dark);
      await device.preferences.setLoadThirdPartyArtwork(false);

      final preview = await device.import(
        plainFile(payload(preferences: {'trueBlack': true})),
      );

      expect(
        preview.preferenceChanges.single.setting,
        ImportedSetting.trueBlack,
      );
      final after = await device.preferences.read();
      expect(after.themeMode, AppThemeMode.dark);
      expect(after.loadThirdPartyArtwork, false);
      expect(after.trueBlack, true);
    });

    for (final (name, wrong) in <(String, Map<String, Object?>)>[
      ('a theme that is none', {'themeMode': 'sepia'}),
      ('a theme that is no text', {'themeMode': 1}),
      ('a switch that is no boolean', {'loadThirdPartyArtwork': 'false'}),
      ('a view that is no object', {'view': <Object>[]}),
      (
        'a view of a profile not in the file',
        {
          'view': {uuid(9): <String, Object?>{}},
        },
      ),
      (
        'add choices without a root folder',
        {
          'lastAddChoices': {uuid(2): <String, Object?>{}},
        },
      ),
    ]) {
      test('with $name refuse the file', () async {
        final file = plainFile(
          payload(
            profiles: [profileJson(1, 'Restored')],
            instances: [instanceJson(2, 'Movies', profile: 1)],
            preferences: {...defaultPreferences, ...wrong},
          ),
        );

        expect(await device.refusal(file), BackupProblem.invalidContent);
      });
    }
  });

  group('is refused', () {
    Future<void> expectInvalid(Map<String, Object?> change) async {
      final file = await encryptedFile(
        payload(
          profiles: [profileJson(1, 'Restored')],
          instances: [
            {...instanceJson(2, 'Movies', profile: 1), ...change},
          ],
        ),
      );

      expect(
        await device.refusal(file, passphrase),
        BackupProblem.invalidContent,
      );
    }

    test('an authKind the service does not offer', () async {
      await expectInvalid({'authKind': 'none'});
    });

    test('a pin that is not as the app stores one', () async {
      await expectInvalid({'certPin': pin.toUpperCase()});
    });

    test('an id that differs from others only in case', () async {
      await expectInvalid({'id': 'AAAAAAAA-0000-4000-8000-000000000000'});
    });

    test('a position with none after it', () async {
      await expectInvalid({'sortOrder': 0x80000000});
    });

    test('a credential in an unencrypted file', () async {
      final file = plainFile(
        payload(
          profiles: [profileJson(1, 'Restored')],
          instances: [
            instanceJson(2, 'Movies', profile: 1, credential: {'apiKey': 'zq'}),
          ],
        ),
      );

      expect(await device.refusal(file), BackupProblem.invalidContent);
    });

    test('a kdf with less memory than Argon2 takes', () async {
      final json = jsonOf(await encryptedFile(payload()));
      ((json['payload']! as Map)['kdf']! as Map)['memoryKiB'] = 7;

      expect(
        await device.refusal(bytesOf(json), passphrase),
        BackupProblem.unsupportedEncryption,
      );
    });
  });

  test('only the certificates of an authority are stored', () async {
    final local = await device.add('Movies');

    await importPlain([replacing(local, customCa: 'a note\n$ca')]);

    expect((await saved(local.id)).customCa, ca);
  });

  test('updatedAt is later, even if the clock is not', () async {
    // The backup is dated before the instance was added.
    final local = await device.add('Movies');

    await importPlain([replacing(local)]);

    expect((await saved(local.id)).updatedAt.isAfter(local.updatedAt), isTrue);
  });

  test('a preview holds for one import', () async {
    final preview = await device.preview(
      plainFile(
        payload(
          profiles: [profileJson(1, 'Restored')],
          instances: [instanceJson(2, 'Movies', profile: 1)],
        ),
      ),
    );
    ok(await device.backup.apply(preview));
    final before = await device.snapshot();

    expect(
      await device.backup.apply(preview),
      isA<Err<void, BackupProblem>>().having(
        (result) => result.error,
        'error',
        BackupProblem.outdatedPreview,
      ),
    );
    expect(await device.snapshot(), before);
  });

  group('an export fails rather than leave something out', () {
    Future<void> expectProblem(BackupProblem problem, [String? phrase]) async {
      expect(
        await device.backup.export(passphrase: phrase),
        isA<Err<Object?, BackupProblem>>().having(
          (result) => result.error,
          'error',
          problem,
        ),
      );
    }

    test('of an instance that cannot be read', () async {
      final local = await device.add('Movies');
      await device.database.customStatement(
        "UPDATE instances SET auth_kind = 'magic' WHERE id = ?",
        [local.id],
      );

      await expectProblem(BackupProblem.unreadableRecord);
    });

    test('of a credential that cannot be read', () async {
      final local = await device.add('Movies');
      device.secrets.values['cred/${local.id}'] = 'zq-garbage';

      await expectProblem(BackupProblem.unreadableRecord, passphrase);
      expect(device.log.entries.join('\n'), isNot(contains('zq-garbage')));
    });

    test('of an instance that an import would refuse', () async {
      final local = await device.add('Movies');
      await (device.database.update(device.database.instances)
            ..where((row) => row.id.equals(local.id)))
          .write(const InstancesCompanion(serviceType: Value('gone')));

      await expectProblem(BackupProblem.invalidContent);
    });
  });
}
