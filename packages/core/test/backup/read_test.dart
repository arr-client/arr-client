/// What an import refuses before it looks at records: limits, tampering and
/// wrong passphrases (contracts/backup-format.md).
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final body = payload(
    profiles: [profileJson(1, 'Restored')],
    instances: [
      instanceJson(
        2,
        'Movies',
        profile: 1,
        credential: {'apiKey': 'zq-secret-key'},
      ),
    ],
  );
  final plain = payload(profiles: [profileJson(1, 'Restored')]);

  late Device device;
  late String before;

  setUp(() async {
    device = await Device.fresh();
    before = await device.snapshot();
  });

  Future<void> expectRefused(
    List<int> file,
    Object problem, {
    String? phrase = passphrase,
  }) async {
    final result = await device.backup.read(file, passphrase: phrase);

    expect(
      result,
      isA<Err<SetupFile, BackupProblem>>().having(
        (result) => result.error,
        'error',
        problem,
      ),
    );
    expect(await device.snapshot(), before);
  }

  Future<SetupFile> read(List<int> file, [String? phrase = passphrase]) async =>
      ok(await device.backup.read(file, passphrase: phrase));

  /// [file] with [change] made to its JSON.
  List<int> edited(
    List<int> file,
    void Function(Map<String, Object?> json) change,
  ) {
    final json = jsonOf(file);
    change(json);
    return bytesOf(json);
  }

  Map<String, Object?> part(Map<String, Object?> json, String name) =>
      json[name]! as Map<String, Object?>;

  group('a good file', () {
    test('without credentials is read, which changes nothing', () async {
      final file = await read(plainFile(plain), null);

      expect(file.includesCredentials, false);
      expect(file.createdAt, DateTime.parse(exportTime));
      expect(await device.snapshot(), before);
    });

    test('with credentials is read, which changes nothing', () async {
      final file = await read(await encryptedFile(body));

      expect(file.includesCredentials, true);
      expect(await device.snapshot(), before);
    });

    test('written by other libraries is restored', () async {
      final golden = File('test/backup/golden_v1.arrclient.json')
          .readAsBytesSync();
      const id = '22222222-2222-4222-8222-222222222222';

      await device.import(golden, 'correct horse bättery');

      expect(await device.profileNames(), ['Golden']);
      final instance = (await device.profiles.instance(id))!;
      expect(instance.url, Uri.parse('https://nas.test:7878/radarr'));
      final stored = (await device.profiles.credential(id))!;
      expect(stored.apiKey, 'zq-golden-key');
      expect(stored.customHeaders, {'X-Proxy-Id': 'zq-golden-header'});
      final preferences = await device.preferences.read();
      expect(preferences.themeMode, AppThemeMode.dark);
      expect(preferences.loadThirdPartyArtwork, false);
      expect(await device.subscriptions(), {(id, 'imported', true)});
    });
  });

  group('limits', () {
    List<int> padded(List<int> file, int length) => [
      ...file,
      ...List.filled(length - file.length, 0x20),
    ];

    test('a file of exactly 1 MiB is read', () async {
      await read(padded(plainFile(plain), maximumFileBytes), null);
    });

    test('a file over 1 MiB is refused', () async {
      await expectRefused(
        padded(plainFile(plain), maximumFileBytes + 1),
        BackupProblem.tooLarge,
      );
      await expectRefused(
        padded(await encryptedFile(body), maximumFileBytes + 1),
        BackupProblem.tooLarge,
      );
    });

    for (final (name, format) in [
      ('another format', 'other-setup'),
      ('no format', null),
    ]) {
      test('$name is refused', () async {
        await expectRefused(
          bytesOf(envelope(plain, encrypted: false, format: format)),
          BackupProblem.notASetupFile,
        );
      });
    }

    test('a newer version is refused', () async {
      await expectRefused(
        bytesOf(envelope(plain, encrypted: false, version: 2)),
        BackupProblem.newerVersion,
      );
      await expectRefused(
        edited(await encryptedFile(body), (json) => json['version'] = 2),
        BackupProblem.newerVersion,
      );
    });

    for (final version in <Object?>[null, 0, -1, '1', 1.5]) {
      test('the version $version is refused', () async {
        await expectRefused(
          bytesOf(envelope(plain, encrypted: false, version: version)),
          isIn([BackupProblem.notASetupFile, BackupProblem.newerVersion]),
        );
      });
    }

    for (final (name, bytes) in <(String, List<int>)>[
      ('nothing', []),
      ('not JSON', utf8.encode('{"format":')),
      ('not UTF-8', [0xff, 0xfe, 0x7b, 0x7d]),
      ('a JSON array', utf8.encode('[]')),
      ('deeply nested', utf8.encode('[' * 100000)),
    ]) {
      test('$name is refused', () async {
        await expectRefused(bytes, BackupProblem.notASetupFile);
      });
    }

    for (final (name, json) in <(String, Map<String, Object?>)>[
      ('without a payload', envelope(null, encrypted: false)),
      ('with a list as payload', envelope(<Object>[], encrypted: false)),
      ('not saying whether encrypted', envelope(plain, encrypted: false))
        ..$2.remove('encrypted'),
      ('claiming to be encrypted', envelope(plain, encrypted: true)),
    ]) {
      test('a file $name is refused', () async {
        await expectRefused(
          bytesOf(json),
          isIn([
            BackupProblem.notASetupFile,
            BackupProblem.invalidContent,
            BackupProblem.unsupportedEncryption,
          ]),
        );
      });
    }

    test('an encrypted payload marked as plain is refused', () async {
      await expectRefused(
        edited(await encryptedFile(body), (json) => json['encrypted'] = false),
        isIn([BackupProblem.notASetupFile, BackupProblem.invalidContent]),
      );
    });

    // Were any of the large values used, the test would not end in time.
    for (final (field, value) in <(String, Object?)>[
      ('memoryKiB', 131073),
      ('memoryKiB', 1 << 31),
      ('memoryKiB', 0),
      ('memoryKiB', -65536),
      ('memoryKiB', '65536'),
      ('memoryKiB', null),
      ('iterations', 11),
      ('iterations', 1 << 31),
      ('iterations', 0),
      ('iterations', 1.5),
      ('parallelism', 0),
      ('parallelism', 2),
      ('name', 'pbkdf2'),
      ('name', 'argon2i'),
      ('salt', 'not base64!'),
    ]) {
      test('kdf $field $value is refused', () async {
        await expectRefused(
          edited(
            await encryptedFile(body),
            (json) => part(part(json, 'payload'), 'kdf')[field] = value,
          ),
          BackupProblem.unsupportedEncryption,
        );
      });
    }

    for (final length in [0, 15, 17]) {
      test('a salt of $length bytes is refused', () async {
        await expectRefused(
          edited(
            await encryptedFile(body),
            (json) => part(part(json, 'payload'), 'kdf')['salt'] = base64
                .encode(List.filled(length, 1)),
          ),
          BackupProblem.unsupportedEncryption,
        );
      });
    }

    // Sealed properly, so that nothing but the length is wrong.
    for (final length in [8, 16]) {
      test('a nonce of $length bytes is refused', () async {
        await expectRefused(
          await encryptedFile(body, nonceLength: length),
          BackupProblem.unsupportedEncryption,
        );
      });
    }

    test('another cipher is refused', () async {
      await expectRefused(
        edited(
          await encryptedFile(body),
          (json) => part(json, 'payload')['cipher'] = 'aes-128-gcm',
        ),
        BackupProblem.unsupportedEncryption,
      );
    });

    test('the largest iterations are accepted', () async {
      await read(await encryptedFile(body, iterations: 10));
    });

    test('the largest memory is accepted', () async {
      await read(await encryptedFile(body, memoryKiB: 131072));
    });
  });

  group('encryption', () {
    test('needs a passphrase', () async {
      await expectRefused(
        await encryptedFile(body),
        BackupProblem.passphraseRequired,
        phrase: null,
      );
    });

    for (final wrong in ['', 'zq passphrase 889', '$passphrase ']) {
      test('is not opened by "$wrong"', () async {
        await expectRefused(
          await encryptedFile(body),
          BackupProblem.wrongPassphraseOrDamaged,
          phrase: wrong,
        );
      });
    }

    /// Flips one bit of a base64 field, [at] counted from the end if negative.
    void flip(Map<String, Object?> json, String field, int at) {
      final bytes = base64.decode(json[field]! as String).toList();
      bytes[at < 0 ? bytes.length + at : at] ^= 1;
      json[field] = base64.encode(bytes);
    }

    for (final (name, change)
        in <(String, void Function(Map<String, Object?>))>[
          ('the first byte of the data', (body) => flip(body, 'data', 0)),
          ('the last byte of the tag', (body) => flip(body, 'data', -1)),
          ('the nonce', (body) => flip(body, 'nonce', 0)),
          (
            'the salt',
            (body) => flip(body['kdf']! as Map<String, Object?>, 'salt', 0),
          ),
          (
            'the iterations',
            (body) => (body['kdf']! as Map<String, Object?>)['iterations'] = 2,
          ),
          (
            'the memory',
            (body) => (body['kdf']! as Map<String, Object?>)['memoryKiB'] = 72,
          ),
        ]) {
      test('a change of $name is noticed', () async {
        await expectRefused(
          edited(
            await encryptedFile(body),
            (json) => change(part(json, 'payload')),
          ),
          BackupProblem.wrongPassphraseOrDamaged,
        );
      });
    }

    for (final (name, length) in [
      ('cut short', -1),
      ('shorter than a tag', 15),
      ('empty', 0),
    ]) {
      test('data $name is refused', () async {
        await expectRefused(
          edited(await encryptedFile(body), (json) {
            final envelope = part(json, 'payload');
            final data = base64.decode(envelope['data']! as String);
            envelope['data'] = base64.encode(
              data.sublist(0, length < 0 ? data.length + length : length),
            );
          }),
          BackupProblem.wrongPassphraseOrDamaged,
        );
      });
    }

    // The format and version are authenticated with the data.
    for (final aad in ['', 'arr-client-setup:2', 'other-setup:1']) {
      test('data sealed with the associated data "$aad" is refused', () async {
        await expectRefused(
          await encryptedFile(body, aad: aad),
          BackupProblem.wrongPassphraseOrDamaged,
        );
      });
    }

    test('what opens but is not a payload is refused', () async {
      await expectRefused(
        await encryptedFile(['not', 'a', 'payload']),
        BackupProblem.invalidContent,
      );
    });

    test('a changed export is refused', () async {
      final source = await Device.fresh();
      await source.add(
        'Movies',
        credential: const Credential(apiKey: 'zq-secret-key'),
      );

      await expectRefused(
        edited(
          await source.export(passphrase),
          (json) => flip(part(json, 'payload'), 'data', 5),
        ),
        BackupProblem.wrongPassphraseOrDamaged,
      );
    });

    test('keeps the passphrase out of the log', () async {
      await device.backup.read(
        await encryptedFile(body),
        passphrase: 'zq wrong phrase',
      );
      await read(await encryptedFile(body));

      final text = device.log.entries.join('\n');
      expect(text, isNot(contains('zq wrong phrase')));
      expect(text, isNot(contains(passphrase)));
      expect(text, isNot(contains('zq-secret-key')));
    });
  });
}
