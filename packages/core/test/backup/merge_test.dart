/// Names, preferences and the fresh install (contracts/backup-format.md).
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// [base] with a number after it, however it is set off.
Matcher _numbered(String base) =>
    matches(RegExp('^${RegExp.escape(base)}\\W*\\d+\\W*\$'));

void main() {
  late Device device;

  setUp(() async => device = await Device.fresh());

  Map<String, Object?> own(String name) => {
    'id': device.home,
    'name': name,
    'sortOrder': 0,
  };

  group('preferences', () {
    test('replace the current ones, as the preview lists', () async {
      await device.preferences.setTrueBlack(true);

      final preview = await device.preview(
        plainFile(
          payload(
            preferences: {
              'themeMode': 'dark',
              'trueBlack': true,
              'dynamicColor': false,
              'loadThirdPartyArtwork': false,
            },
          ),
        ),
      );

      expect(
        {for (final c in preview.preferenceChanges) c.setting: (c.from, c.to)},
        {
          ImportedSetting.themeMode: (AppThemeMode.system, AppThemeMode.dark),
          ImportedSetting.dynamicColor: (true, false),
          ImportedSetting.loadThirdPartyArtwork: (true, false),
        },
      );
      expect((await device.preferences.read()).loadThirdPartyArtwork, true);

      ok(await device.backup.apply(preview));

      final after = await device.preferences.read();
      expect(after.themeMode, AppThemeMode.dark);
      expect(after.trueBlack, true);
      expect(after.dynamicColor, false);
      expect(after.loadThirdPartyArtwork, false);
    });

    test('that stay the same are not listed', () async {
      final preview = await device.preview(plainFile(payload()));

      expect(preview.preferenceChanges, isEmpty);
    });

    test('turning third-party artwork back on is listed', () async {
      await device.preferences.setLoadThirdPartyArtwork(false);

      final preview = await device.preview(plainFile(payload()));

      expect(
        preview.preferenceChanges.single.setting,
        ImportedSetting.loadThirdPartyArtwork,
      );
    });

    for (final (name, lock) in [
      ('turn app lock on', {'enabled': true, 'delaySeconds': 600}),
      ('turn app lock off', {'enabled': false, 'delaySeconds': 0}),
    ]) {
      test('cannot $name or choose the active profile', () async {
        const mine = AppLock(enabled: true, delaySeconds: 30);
        await device.preferences.setAppLock(mine);
        await device.add('Movies');

        await device.import(
          plainFile(
            payload(
              profiles: [profileJson(1, 'Restored')],
              preferences: {
                ...defaultPreferences,
                'appLock': lock,
                'activeProfileId': uuid(1),
              },
            ),
          ),
        );

        expect((await device.preferences.read()).appLock, mine);
        expect(await device.activeProfile(), device.home);
      });
    }

    test('of a fresh install gain no app lock from a file', () async {
      await device.import(
        plainFile(
          payload(
            preferences: {
              ...defaultPreferences,
              'appLock': {'enabled': true, 'delaySeconds': 0},
              'activeProfileId': uuid(9),
            },
          ),
        ),
      );

      expect((await device.preferences.read()).appLock, const AppLock());
      expect(await device.activeProfile(), device.home);
    });
  });

  group('a fresh install', () {
    List<int> file() => plainFile(
      payload(
        profiles: [profileJson(1, 'Default'), profileJson(2, 'Away')],
        instances: [instanceJson(3, 'Movies', profile: 1)],
      ),
    );

    test('loses its empty profile to the first imported one', () async {
      final preview = await device.preview(file());

      expect(preview.removedProfileId, device.home);
      // The restored "Default" keeps its name.
      expect(preview.profiles.map((p) => p.name), ['Default', 'Away']);

      ok(await device.backup.apply(preview));

      expect(await device.profileNames(), ['Default', 'Away']);
      expect((await device.profiles.profiles()).first.id, uuid(1));
      expect(await device.activeProfile(), uuid(1));
    });

    test('keeps its profile if the file replaces it', () async {
      await device.import(
        plainFile(payload(profiles: [profileJson(1, 'Away'), own('Restored')])),
      );

      expect(await device.profileNames(), containsAll(['Away', 'Restored']));
      expect(await device.activeProfile(), device.home);
    });

    test('keeps its profile if the file has none', () async {
      final preview = await device.import(plainFile(payload()));

      expect(preview.removedProfileId, isNull);
      expect(await device.profileNames(), ['Default']);
      expect(await device.activeProfile(), device.home);
    });

    test('is not one once its profile has an instance', () async {
      await device.add('Local');

      final preview = await device.import(file());

      expect(preview.removedProfileId, isNull);
      expect(await device.activeProfile(), device.home);
      final names = await device.profileNames();
      expect(names, ['Default', _numbered('Default'), 'Away']);
      expect(preview.profiles.first.name, names[1]);
    });

    test('is not one with a second profile', () async {
      await device.profile('Mine');

      final preview = await device.import(file());

      expect(preview.removedProfileId, isNull);
      expect(await device.activeProfile(), device.home);
      expect(await device.profiles.profiles(), hasLength(4));
    });
  });

  group('a name in use', () {
    setUp(() => device.add('Movies'));

    test('gets a number, shown in the preview', () async {
      final preview = await device.preview(
        plainFile(payload(profiles: [profileJson(1, 'default')])),
      );
      final shown = preview.profiles.single;

      expect(shown.nameInFile, 'default');
      expect(shown.name, _numbered('default'));

      ok(await device.backup.apply(preview));

      expect(await device.profileNames(), ['Default', shown.name]);
    });

    test('among the instances of a profile gets one too', () async {
      final preview = await device.import(
        plainFile(
          payload(
            profiles: [own('Default')],
            instances: [
              {
                ...instanceJson(2, 'MOVIES', profile: 1),
                'profileId': device.home,
              },
            ],
          ),
        ),
      );
      final shown = preview.instances.single;

      expect(shown.nameInFile, 'MOVIES');
      expect(shown.name, _numbered('MOVIES'));
      expect((await device.profiles.instance(uuid(2)))!.name, shown.name);
    });

    test('in another profile is left alone', () async {
      final preview = await device.import(
        plainFile(
          payload(
            profiles: [profileJson(1, 'Away')],
            instances: [instanceJson(2, 'Movies', profile: 1)],
          ),
        ),
      );

      expect(preview.instances.single.name, 'Movies');
    });

    test('by the record being replaced is not in use', () async {
      final source = await Device.fresh();
      await source.add('Movies');
      final file = await source.export();
      await device.import(file);
      final names = await device.profileNames();

      final again = await device.import(file);

      expect(again.profiles.map((p) => p.name), [names.last]);
      expect(again.instances.single.name, 'Movies');
      expect(await device.profileNames(), names);
    });

    test('is numbered past numbers already taken', () async {
      final first = await device.import(
        plainFile(payload(profiles: [profileJson(1, 'Default')])),
      );
      final second = await device.import(
        plainFile(payload(profiles: [profileJson(2, 'Default')])),
      );

      expect(second.profiles.single.name, _numbered('Default'));
      expect(second.profiles.single.name, isNot(first.profiles.single.name));
    });

    test('twice in one file ends up different', () async {
      final preview = await device.import(
        plainFile(
          payload(
            profiles: [profileJson(1, 'Default'), profileJson(2, 'default')],
          ),
        ),
      );

      final names = await device.profileNames();
      expect(names.map((n) => n.toLowerCase()).toSet(), hasLength(3));
      expect(preview.profiles.map((p) => p.name), names.skip(1));
    });

    for (final (what, long) in [
      ('letters', 'abcdefghij' * 4),
      // Forty characters of two UTF-16 code units each.
      ('emoji', '\u{1F3AC}' * 40),
    ]) {
      test('of 40 $what is shortened to make room', () async {
        await device.profile(long);
        await device.add(long);

        final preview = await device.import(
          plainFile(
            payload(
              profiles: [profileJson(1, long), own('Default')],
              instances: [
                {
                  ...instanceJson(2, long, profile: 1),
                  'profileId': device.home,
                },
              ],
            ),
          ),
        );

        for (final name in [
          preview.profiles.first.name,
          preview.instances.single.name,
        ]) {
          expect(name, isNot(long));
          expect(name.runes.length, lessThanOrEqualTo(40));
          expect(name, matches(RegExp(r'\d')));
          // Shortened no more than needed, and between characters.
          expect(name.runes.take(30), long.runes.take(30));
          expect(
            name.runes.where((rune) => rune >= 0xD800 && rune <= 0xDFFF),
            isEmpty,
          );
        }
      });
    }
  });
}
