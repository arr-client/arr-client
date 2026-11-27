/// Records, credentials and trust on import (contracts/backup-format.md).
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../network/support.dart'
    show credential, secretValues, sessionCookie, apiKey;
import 'support.dart';

const _url = 'http://nas.test:7878/radarr';

void main() {
  final ca = File('test/network/certs/ca.pem').readAsStringSync();

  late Device device;

  setUp(() async => device = await Device.fresh());

  /// A file with one profile of its own and [instances] in it.
  List<int> fileOf(List<Map<String, Object?>> instances) => plainFile(
    payload(profiles: [profileJson(1, 'Restored')], instances: instances),
  );

  Future<List<int>> sealedOf(List<Map<String, Object?>> instances) =>
      encryptedFile(
        payload(profiles: [profileJson(1, 'Restored')], instances: instances),
      );

  group('a round trip', () {
    late Device source;
    late Instance movies;
    late Instance subtitles;

    setUp(() async {
      source = await Device.fresh();
      movies = await source.add(
        'Movies',
        credential: credential,
        certPin: pin,
        customCa: ca,
      );
      subtitles = await source.add(
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
      await source.signIn(movies.id, sessionCookie);
      await source.subscribe(movies.id, 'imported');
      await source.preferences.saveView(
        source.home,
        MediaKind.movie,
        LibraryView(
          layout: LibraryLayout.list,
          filters: LibraryFilters(
            text: 'alien',
            tags: {InstanceOptionId(movies.id, 3)},
          ),
          instanceScope: movies.id,
        ),
      );
      await source.preferences.saveLastAddChoices(
        movies.id,
        const AddChoices(
          rootFolderId: 1,
          qualityProfileId: 4,
          monitorOptionId: 'movieOnly',
          searchNow: true,
          tagIds: {3},
        ),
      );
    });

    Future<void> expectRecords() async {
      expect(await device.profileNames(), ['Default']);
      expect(await device.activeProfile(), source.home);
      final restored = (await device.profiles.instance(movies.id))!;
      expect(restored.profileId, source.home);
      expect(restored.name, 'Movies');
      expect(restored.url, movies.url);
      expect(restored.authKind, AuthKind.apiKey);
      expect(restored.certPin, pin);
      expect(restored.customCa, ca);
      expect(restored.createdAt, movies.createdAt);
      final links = (await device.profiles.instance(subtitles.id))!.links;
      expect(links.single.instanceId, movies.id);
      expect(await device.subscriptions(), {(movies.id, 'imported', true)});
      expect(
        await device.preferences.view(source.home, MediaKind.movie),
        await source.preferences.view(source.home, MediaKind.movie),
      );
      final choices = (await device.preferences.lastAddChoices(movies.id))!;
      expect(choices.qualityProfileId, 4);
      expect(choices.monitorOptionId, 'movieOnly');
      expect(choices.tagIds, {3});
    }

    test('with credentials restores all but the session', () async {
      await device.import(await source.export(passphrase), passphrase);

      await expectRecords();
      final stored = (await device.profiles.credential(movies.id))!;
      expect(stored.apiKey, apiKey);
      expect(stored.username, credential.username);
      expect(stored.password, credential.password);
      expect(stored.basicUser, credential.basicUser);
      expect(stored.basicPassword, credential.basicPassword);
      expect(stored.customHeaders, credential.customHeaders);
      expect(stored.sessionCookie, isNull);
    });

    test('without credentials restores the records alone', () async {
      await device.import(await source.export());

      await expectRecords();
      expect(device.secrets.values, isEmpty);
    });
  });

  group('before confirmation', () {
    test('nothing changes, and the preview says what would', () async {
      final kept = await device.add('Kept');
      final changed = await device.add(
        'Changed',
        url: 'http://old.test/radarr',
        credential: const Credential(apiKey: apiKey),
      );
      final same = await device.add('Same', url: _url);
      final file = plainFile(
        payload(
          profiles: [
            {'id': device.home, 'name': 'Default', 'sortOrder': 0},
            profileJson(1, 'Restored'),
          ],
          instances: [
            {
              ...instanceJson(
                2,
                'Changed',
                profile: 1,
                url: 'http://new.test/radarr',
              ),
              'id': changed.id,
              'profileId': device.home,
            },
            {
              ...instanceJson(3, 'Same', profile: 1),
              'id': same.id,
              'profileId': device.home,
            },
            instanceJson(
              4,
              'Pinned',
              profile: 1,
              url: 'https://pinned.test',
              certPin: pin,
              customCa: ca,
            ),
          ],
        ),
      );
      final before = await device.snapshot();

      final preview = await device.preview(file);

      expect(await device.snapshot(), before);
      expect(
        {for (final p in preview.profiles) p.id: p.action},
        {device.home: ImportAction.replace, uuid(1): ImportAction.add},
      );
      final instances = {for (final i in preview.instances) i.id: i};
      expect(instances.keys, {changed.id, same.id, uuid(4)});
      expect(instances.keys, isNot(contains(kept.id)));
      expect(instances[changed.id]!.action, ImportAction.replace);
      expect(
        instances[changed.id]!.previousUrl,
        Uri.parse('http://old.test/radarr'),
      );
      expect(instances[changed.id]!.url, Uri.parse('http://new.test/radarr'));
      expect(instances[same.id]!.action, ImportAction.replace);
      expect(instances[same.id]!.previousUrl, isNull);
      expect(instances[uuid(4)]!.action, ImportAction.add);
      expect(instances[uuid(4)]!.profileId, uuid(1));
      expect(instances[uuid(4)]!.certPin, pin);
      expect(instances[uuid(4)]!.customCa, ca);
    });

    test('a change of the path alone is also an address change', () async {
      final local = await device.add('Movies');

      final preview = await device.preview(
        plainFile(
          payload(
            profiles: [
              {'id': device.home, 'name': 'Default', 'sortOrder': 0},
            ],
            instances: [
              {
                ...instanceJson(
                  2,
                  'Movies',
                  profile: 1,
                  url: 'http://nas.test:7878/other',
                ),
                'id': local.id,
                'profileId': device.home,
              },
            ],
          ),
        ),
      );

      expect(preview.instances.single.previousUrl, local.url);
    });
  });

  test('what the file does not name is kept', () async {
    final away = await device.profile('Away');
    final kept = await device.add(
      'Kept',
      profileId: away,
      credential: const Credential(apiKey: apiKey),
    );
    await device.subscribe(kept.id, 'imported');

    await device.import(fileOf([instanceJson(2, 'New', profile: 1)]));

    expect(
      await device.profileNames(),
      unorderedEquals(['Default', 'Away', 'Restored']),
    );
    expect((await device.profiles.instance(kept.id))!.name, 'Kept');
    expect((await device.profiles.credential(kept.id))!.apiKey, apiKey);
    expect(await device.subscriptions(), {(kept.id, 'imported', true)});
  });

  group('replacing an instance', () {
    late Instance local;

    setUp(() async {
      local = await device.add(
        'Movies',
        authKind: AuthKind.userPassword,
        credential: const Credential(
          apiKey: apiKey,
          username: 'zq-user',
          password: 'zq-old-pass',
          customHeaders: {'X-Proxy-Id': 'zq-header'},
        ),
        certPin: pin,
      );
      await device.signIn(local.id, sessionCookie);
    });

    Map<String, Object?> replacement({
      String url = _url,
      String authKind = 'userPassword',
      Map<String, Object?>? credential,
      String? certPin,
    }) => {
      ...instanceJson(
        2,
        'Movies',
        profile: 1,
        url: url,
        authKind: authKind,
        credential: credential,
        certPin: certPin,
      ),
      'id': local.id,
      'profileId': device.home,
    };

    /// A file that replaces [local], which stays in its profile.
    Map<String, Object?> bodyOf(Map<String, Object?> instance) => payload(
      profiles: [
        {'id': device.home, 'name': 'Default', 'sortOrder': 0},
      ],
      instances: [instance],
    );

    Future<void> importPlain(Map<String, Object?> instance) =>
        device.import(plainFile(bodyOf(instance)));

    Future<void> importSealed(Map<String, Object?> instance) async =>
        device.import(await encryptedFile(bodyOf(instance)), passphrase);

    Future<Instance> saved() async =>
        (await device.profiles.instance(local.id))!;

    Future<Credential> stored() async =>
        (await device.profiles.credential(local.id)) ?? const Credential();

    /// That nothing secret of the instance is left anywhere.
    void expectPurged() {
      final text = device.secrets.values.values.join();
      for (final secret in [
        apiKey,
        'zq-user',
        'zq-old-pass',
        'zq-header',
        'zq-delta-444',
      ]) {
        expect(text, isNot(contains(secret)));
      }
    }

    for (final (change, url) in [
      ('host', 'http://other.test:7878/radarr'),
      ('port', 'http://nas.test:7879/radarr'),
      ('scheme to https', 'https://nas.test:7878/radarr'),
    ]) {
      test(
        'at another $change, without a credential, drops secrets and pin',
        () async {
          await importPlain(replacement(url: url));

          expect((await saved()).url, Uri.parse(url));
          expect((await saved()).certPin, isNull);
          expectPurged();
        },
      );
    }

    test('from https to http drops them too', () async {
      await importPlain(replacement(url: 'https://nas.test:7878/radarr'));
      ok(
        await device.profiles.updateInstance(
          local.id,
          InstanceDraft(
            name: 'Movies',
            serviceType: 'radarr',
            url: Uri.parse('https://nas.test:7878/radarr'),
            authKind: AuthKind.userPassword,
          ),
          credential: const Credential(password: 'zq-old-pass'),
        ),
      );

      await importPlain(replacement());

      expectPurged();
    });

    test('at another origin takes the pin the file shows', () async {
      await importPlain(
        replacement(url: 'https://other.test', certPin: otherPin),
      );

      expect((await saved()).certPin, otherPin);
      expectPurged();
    });

    for (final (what, url) in [
      ('the same address', _url),
      ('another path', 'http://nas.test:7878/movies'),
    ]) {
      test('at $what, without a credential, keeps the secrets', () async {
        await importPlain(replacement(url: url));

        expect((await stored()).apiKey, apiKey);
        expect((await stored()).password, 'zq-old-pass');
        expect((await stored()).sessionCookie, sessionCookie);
      });
    }

    test('with another authKind drops the session alone', () async {
      await importPlain(replacement(authKind: 'apiKey'));

      expect((await stored()).apiKey, apiKey);
      expect((await stored()).sessionCookie, isNull);
    });

    test('with another credential drops the session', () async {
      await importSealed(replacement(credential: {'username': 'zq-new-user'}));

      // The whole credential is replaced, not merged.
      expect((await stored()).username, 'zq-new-user');
      expect((await stored()).password, isNull);
      expect((await stored()).apiKey, isNull);
      expect((await stored()).customHeaders, isEmpty);
      expect((await stored()).sessionCookie, isNull);
    });

    test('at another origin uses only the credential of the file', () async {
      await importSealed(
        replacement(
          url: 'https://other.test',
          certPin: otherPin,
          credential: {'username': 'zq-new-user', 'password': 'zq-new-pass'},
        ),
      );

      expect((await stored()).username, 'zq-new-user');
      expect((await stored()).password, 'zq-new-pass');
      expect((await saved()).certPin, otherPin);
      expectPurged();
    });

    test('at another origin, an empty credential keeps nothing', () async {
      await importSealed(replacement(url: 'http://other.test', credential: {}));

      expect((await saved()).certPin, isNull);
      expectPurged();
    });

    test('never takes a session cookie from the file', () async {
      await importSealed(
        replacement(
          url: 'http://other.test',
          credential: {'apiKey': 'zq-new', 'sessionCookie': 'SID=zq-planted'},
        ),
      );

      expect((await stored()).apiKey, 'zq-new');
      expect((await stored()).sessionCookie, isNull);
      expect(device.secrets.values.values.join(), isNot(contains('planted')));
    });

    test('never takes a credential from an unencrypted file', () async {
      final before = await device.snapshot();
      final file = plainFile(
        bodyOf(
          replacement(
            url: 'http://other.test',
            credential: {'apiKey': 'zq-planted'},
          ),
        ),
      );

      // Refused, or imported without it.
      if (await device.refusal(file) == null) {
        await device.import(file);
        expectPurged();
      } else {
        expect(await device.snapshot(), before);
      }
      expect(device.secrets.values.values.join(), isNot(contains('planted')));
    });

    test('never pairs the old secrets with a new origin if the secret store '
        'fails', () async {
      final preview = await device.preview(
        plainFile(bodyOf(replacement(url: 'http://other.test'))),
      );
      device.secrets
        ..failDeletes = true
        ..failWrite = (_) => true;

      try {
        await device.backup.apply(preview);
      } on StateError {
        // As ProfileRepository does when the store fails.
      }

      final url = (await saved()).url;
      final secrets = device.secrets.values.values.join();
      expect(
        url == local.url || !secrets.contains('zq-old-pass'),
        isTrue,
        reason: '$url has the secrets of ${local.url}',
      );
    });

    test('goes by the address saved when confirmed', () async {
      // At the time of the preview the address stays.
      final preview = await device.preview(plainFile(bodyOf(replacement())));
      ok(
        await device.profiles.updateInstance(
          local.id,
          InstanceDraft(
            name: 'Movies',
            serviceType: 'radarr',
            url: Uri.parse('http://moved.test'),
            authKind: AuthKind.userPassword,
          ),
          credential: const Credential(password: 'zq-moved-pass'),
        ),
      );
      final before = await device.snapshot();

      switch (await device.backup.apply(preview)) {
        case Ok():
          expect(
            device.secrets.values.values.join(),
            isNot(contains('zq-moved-pass')),
          );
        case Err(:final error):
          expect(error, BackupProblem.outdatedPreview);
          expect(await device.snapshot(), before);
      }
    });

    test('keeps authFailed when no credential comes with it', () async {
      await device.profiles.markAuthFailed(local.id);

      await importPlain({...replacement(), 'authFailed': false});

      expect((await saved()).authFailed, isTrue);
    });

    test('with another credential clears authFailed', () async {
      await device.profiles.markAuthFailed(local.id);

      await importSealed({
        ...replacement(credential: {'password': 'zq-new-pass'}),
        'authFailed': true,
      });

      expect((await saved()).authFailed, isFalse);
    });

    test('keeps the last probe and drops what the address told', () async {
      final used = (await device.profiles.instanceWithCredential(local.id))!;
      await device.profiles.recordProbe(
        used,
        const ProbeSnapshot(
          product: 'Radarr',
          version: '5',
          capabilities: {CapabilityKind.health},
        ),
      );
      await device.profiles.recordUnsupportedVersion(used, '1');

      await importPlain(replacement(url: 'http://other.test'));

      expect((await saved()).lastProbe?.product, 'Radarr');
      expect((await saved()).detectedVersion, isNull);
      expect((await saved()).unsupportedVersion, isNull);
    });

    test('cannot change its service', () async {
      final before = await device.snapshot();
      final file = plainFile(
        bodyOf({...replacement(), 'serviceType': 'sonarr'}),
      );

      expect(await device.refusal(file), BackupProblem.invalidContent);
      expect(await device.snapshot(), before);
    });
  });

  test('a new instance takes no state from the file', () async {
    await device.import(
      fileOf([
        {
          ...instanceJson(2, 'Movies', profile: 1),
          'authFailed': true,
          'detectedVersion': '9',
          'unsupportedVersion': '1',
          'lastProbe': {
            'product': 'Radarr',
            'version': '9',
            'capabilities': ['health'],
          },
        },
      ]),
    );

    final saved = (await device.profiles.instance(uuid(2)))!;
    expect(saved.authFailed, isFalse);
    expect(saved.detectedVersion, isNull);
    expect(saved.unsupportedVersion, isNull);
    expect(saved.lastProbe, isNull);
  });

  test('imported credentials are kept out of the log', () async {
    await device.import(
      await sealedOf([
        instanceJson(
          2,
          'Movies',
          profile: 1,
          credential: {'apiKey': apiKey, 'password': secretValues.last},
        ),
      ]),
      passphrase,
    );
    device.log.log(LogLevel.info, 'sent $apiKey ${secretValues.last}');

    final text = device.log.entries.join('\n');
    expect(text, isNot(contains(apiKey)));
    expect(text, isNot(contains(secretValues.last)));
    expect(text, isNot(contains(passphrase)));
  });

  test('a failing secret store leaves nothing half imported', () async {
    final local = await device.add(
      'Local',
      credential: const Credential(apiKey: apiKey),
    );
    final preview = await device.preview(
      await encryptedFile(
        payload(
          profiles: [
            {'id': device.home, 'name': 'Renamed', 'sortOrder': 0},
          ],
          instances: [
            {
              ...instanceJson(
                2,
                'Local',
                profile: 1,
                credential: {'apiKey': 'zq-replaced'},
              ),
              'id': local.id,
              'profileId': device.home,
            },
            {
              ...instanceJson(
                3,
                'Second',
                profile: 1,
                credential: {'apiKey': 'zq-second'},
              ),
              'profileId': device.home,
            },
          ],
          preferences: {...defaultPreferences, 'themeMode': 'dark'},
        ),
      ),
      passphrase,
    );
    final before = await device.snapshot();
    device.secrets.failWrite = (key) => key == 'cred/${uuid(3)}';

    await expectLater(device.backup.apply(preview), throwsStateError);

    expect(await device.snapshot(), before);
  });

  group('records are held to the rules of manual entry', () {
    Map<String, Object?> body() => payload(
      profiles: [profileJson(1, 'Restored')],
      instances: [
        instanceJson(2, 'Movies', profile: 1, credential: {'apiKey': 'zq-key'}),
        instanceJson(3, 'Series', profile: 1, serviceType: 'sonarr'),
        instanceJson(4, 'Subtitles', profile: 1, serviceType: 'bazarr'),
      ],
      subscriptions: [
        {'instanceId': uuid(2), 'eventType': 'imported', 'enabled': true},
      ],
    );

    Map<String, Object?> first(Map<String, Object?> body, [String of = '']) =>
        records(body[of.isEmpty ? 'instances' : of]).first;

    void link(Map<String, Object?> body, int from, List<int> to) =>
        records(body['instances'])[from]['links'] = [
          for (final target in to)
            {'type': 'subtitlesFor', 'instanceId': uuid(target)},
        ];

    test('and a file that follows them is imported', () async {
      final good = body();
      link(good, 2, [2, 3]);

      await device.import(await encryptedFile(good), passphrase);

      expect(await device.profiles.instances(uuid(1)), hasLength(3));
    });

    final breaks = <String, void Function(Map<String, Object?>)>{
      'a profile without a name': (b) => first(b, 'profiles')['name'] = '',
      'a profile name of 41': (b) => first(b, 'profiles')['name'] = 'a' * 41,
      'a profile id that is no UUID': (b) {
        first(b, 'profiles')['id'] = 'home';
        for (final instance in records(b['instances'])) {
          instance['profileId'] = 'home';
        }
      },
      'two profiles with one id': (b) =>
          b['profiles'] = [profileJson(1, 'A'), profileJson(1, 'B')],
      'profiles that are no list': (b) => b['profiles'] = {},
      'no instances at all': (b) => b.remove('instances'),
      'no preferences': (b) => b.remove('preferences'),
      'an instance that is no object': (b) => b['instances'] = ['x'],
      'an instance without a name': (b) => first(b)['name'] = '',
      'an instance name of 41': (b) => first(b)['name'] = 'a' * 41,
      'a name that is no text': (b) => first(b)['name'] = 5,
      'an id that is no UUID': (b) {
        first(b)['id'] = '../movies';
        b['subscriptions'] = <Object>[];
      },
      'two instances with one id': (b) =>
          records(b['instances'])[1]['id'] = uuid(2),
      'a profile not in the file': (b) => first(b)['profileId'] = uuid(9),
      'an ftp address': (b) => first(b)['url'] = 'ftp://nas.test',
      'user info in the address': (b) =>
          first(b)['url'] = 'http://u:p@nas.test',
      'a query in the address': (b) => first(b)['url'] = 'http://nas.test?a=1',
      'a fragment in the address': (b) => first(b)['url'] = 'http://nas.test#a',
      'an address without a host': (b) => first(b)['url'] = 'http:///radarr',
      'no address': (b) => first(b).remove('url'),
      'an unknown service': (b) => first(b)['serviceType'] = 'unheard-of',
      'an unknown authKind': (b) => first(b)['authKind'] = 'magic',
      'a certificate pin that is none': (b) => first(b)['certPin'] = 'trust me',
      'an authority that is no certificate': (b) =>
          first(b)['customCa'] = 'trust me',
      'an authority with a private key': (b) => first(b)['customCa'] =
          '$ca\n${File('test/network/certs/leaf.key').readAsStringSync()}',
      'an authority over 64 KiB': (b) =>
          first(b)['customCa'] = ca * (65 * 1024 ~/ ca.length + 1),
      'a Host header': (b) => first(b)['credential'] = {
        'customHeaders': {'Host': 'evil.test'},
      },
      'a header name that is no token': (b) => first(b)['credential'] = {
        'customHeaders': {'X Id\r\n': '1'},
      },
      'a secret that is no text': (b) => first(b)['credential'] = {'apiKey': 5},
      'basic auth where the API key needs the header': (b) {
        first(b)['serviceType'] = 'bearer';
        first(b)['credential'] = {'basicUser': 'u', 'basicPassword': 'p'};
      },
      'a link from a movie service': (b) => link(b, 0, [3]),
      'a link to a subtitle service': (b) => link(b, 2, [4]),
      'a link to nothing': (b) => link(b, 2, [9]),
      'two links to movie services': (b) {
        records(b['instances'])[1]['serviceType'] = 'radarr';
        link(b, 2, [2, 3]);
      },
      'a link into another profile': (b) {
        b['profiles'] = [profileJson(1, 'A'), profileJson(5, 'B')];
        first(b)['profileId'] = uuid(5);
        link(b, 2, [2]);
      },
      'an unknown event type': (b) =>
          first(b, 'subscriptions')['eventType'] = 'everything',
      'a subscription of an instance not in the file': (b) =>
          first(b, 'subscriptions')['instanceId'] = uuid(9),
    };

    for (final MapEntry(key: name, value: damage) in breaks.entries) {
      test('$name refuses the whole file', () async {
        final broken = body();
        damage(broken);
        final before = await device.snapshot();

        expect(
          await device.refusal(await encryptedFile(broken), passphrase),
          BackupProblem.invalidContent,
        );
        expect(await device.snapshot(), before);
      });
    }
  });

  group('notification markers', () {
    // An instance without a marker is one whose baseline is still to be taken,
    // so that nothing older than the import notifies.
    test('are left to be taken anew for what is imported', () async {
      final replaced = await device.add('Replaced');
      final kept = await device.add('Kept');
      await device.mark(replaced.id, 'zq-old-cursor');
      await device.mark(kept.id, 'zq-kept-cursor');

      await device.import(
        plainFile(
          payload(
            profiles: [
              {'id': device.home, 'name': 'Default', 'sortOrder': 0},
            ],
            instances: [
              {
                ...instanceJson(2, 'Replaced', profile: 1),
                'id': replaced.id,
                'profileId': device.home,
              },
              {
                ...instanceJson(3, 'New', profile: 1),
                'profileId': device.home,
                'lastSeenCursor': 'zq-planted',
              },
            ],
          ),
        ),
      );

      expect(await device.marked(), {kept.id});
    });

    test('that a file carries are not imported', () async {
      final body = payload(
        profiles: [profileJson(1, 'Restored')],
        instances: [instanceJson(2, 'Movies', profile: 1)],
      );
      body['eventMarkers'] = [
        {'instanceId': uuid(2), 'eventType': 'imported', 'lastSeenCursor': '9'},
      ];

      // Ignored, or refused as outside the schema.
      if (await device.refusal(plainFile(body)) == null) {
        await device.import(plainFile(body));
      }

      expect(await device.marked(), isEmpty);
    });

    test('of a subscription are not copied with it', () async {
      final source = await Device.fresh();
      final movies = await source.add('Movies');
      await source.subscribe(movies.id, 'imported');
      await source.mark(movies.id, 'zq-cursor');

      await device.import(await source.export());

      expect(await device.subscriptions(), {(movies.id, 'imported', true)});
      expect(await device.marked(), isEmpty);
    });
  });

  test('a replaced instance takes the subscriptions of the file', () async {
    final local = await device.add('Movies');
    await device.subscribe(local.id, 'imported', enabled: false);

    await device.import(
      plainFile(
        payload(
          profiles: [
            {'id': device.home, 'name': 'Default', 'sortOrder': 0},
          ],
          instances: [
            {
              ...instanceJson(2, 'Movies', profile: 1),
              'id': local.id,
              'profileId': device.home,
            },
          ],
          subscriptions: [
            {'instanceId': local.id, 'eventType': 'imported', 'enabled': true},
          ],
        ),
      ),
    );

    expect(await device.subscriptions(), {(local.id, 'imported', true)});
  });

  test('an import is seen by those who follow the profiles', () async {
    var changes = 0;
    final watch = device.profiles.changes.listen((_) => changes++);
    addTearDown(watch.cancel);

    await device.import(fileOf([instanceJson(2, 'Movies', profile: 1)]));
    await pumpEventQueue();

    expect(changes, isNonZero);
  });
}
