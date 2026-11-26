/// Profile and instance validation and credential rules (data-model.md).
///
/// The API these tests expect, all in `lib/src/instances/` and exported by
/// `package:core/core.dart`, next to the plain types already there:
///
/// ```dart
/// final class Profile { String id; String name; int sortOrder; }
///
/// // What the add and edit form saves: the whole editable state.
/// final class InstanceDraft {
///   const InstanceDraft({
///     required String name,
///     required String serviceType,
///     required Uri url,
///     required AuthKind authKind,
///     String? acceptedCertPin, // newly accepted for `url`, see below
///     bool removeCertPin = false, // the user stops trusting the stored one
///     String? customCa, // stored as given; null removes it
///     ProbeSnapshot? probe, // of a successful test of this draft, else null
///     bool authRejected = false, // its test refused the token or login
///     bool enabled = true,
///     List<InstanceLink> links = const [],
///   });
/// }
///
/// enum RuleViolation {
///   nameLength, nameTaken, lastProfile, unknownServiceType,
///   serviceTypeChanged, url, customCaTooLarge, headerName,
///   basicAuthWithApiKey, link,
/// }
///
/// final class ProfileRepository {
///   ProfileRepository({
///     required AppDatabase database,
///     required SecretStore secrets,
///     required DiagnosticLog log,
///     required PreferencesRepository preferences,
///     required Iterable<ServiceModule> modules, // the registry
///     DateTime Function() now = DateTime.now,
///   });
///
///   Future<void> ensureDefaultProfile(); // also if none is active
///   Future<List<Profile>> profiles(); // by sortOrder
///   Future<Result<Profile, RuleViolation>> createProfile(String name);
///   Future<Result<void, RuleViolation>> renameProfile(String id, String name);
///   Future<Result<Profile, RuleViolation>> copyProfile(
///     String id, {required String name});
///   Future<Result<void, RuleViolation>> deleteProfile(String id);
///
///   Future<List<Instance>> instances(String profileId); // by sortOrder
///   Future<Instance?> instance(String id);
///   // Both from one transaction, for sending requests.
///   Future<({Instance instance, Credential? credential})?>
///     instanceWithCredential(String id);
///   Future<Result<Instance, RuleViolation>> addInstance(
///     String profileId, InstanceDraft draft,
///     {Credential credential = const Credential()});
///   Future<Result<Instance, RuleViolation>> updateInstance(
///     String id, InstanceDraft draft,
///     {Credential? credential}); // null keeps the stored one
///   Future<void> deleteInstance(String id);
///
///   Future<Credential?> credential(String instanceId);
///   Future<void> markAuthFailed(String instanceId);
///   Future<void> retryAuth(String instanceId);
/// }
/// ```
///
/// Rules the signatures do not show:
///
/// - A refused operation returns [Err] and changes nothing. A failed secret
///   write throws, and leaves no new profile, instance or secret behind.
/// - `acceptedCertPin`: if given, it is stored. If null, the stored pin is kept
///   unless the scheme, host or port of the url changes, or `removeCertPin`.
/// - `probe`: if given, it sets `lastProbe` and `detectedVersion` (its
///   version). If null and the url changes, `lastProbe` is kept and
///   `detectedVersion` cleared.
/// - `authFailed` is cleared by `retryAuth`, or by an update whose credential
///   differs from the stored one in what the user enters (not the session
///   cookie). Nothing else clears it.
/// - `authRejected` saves the instance with `authFailed` set, also when the
///   update changes the credential.
/// - An update never takes the session cookie of the given credential. It drops
///   the stored one when the origin, authKind or what the user enters changes.
/// - Basic auth is refused with `AuthKind.apiKey` where the module sends its
///   API key in `Authorization`. Rules never test a module id: links go from a
///   `subtitles` module to at most one `movies` and one `series` instance.
/// - Deleting the active profile makes another one active.
/// - Credentials given to or read by the repository are registered with the log
///   before the secret store or the caller gets them, also if refused.
/// - A secret read or write that fails throws and changes nothing, but new
///   credentials can be saved over ones that cannot be read. A failed secret
///   delete is logged, does not stop the deletion of records, and is retried by
///   `ensureDefaultProfile`.
/// - Secrets are erased only after the deletion of their records is saved, and
///   after a failed change they are put back before any other change runs.
library;

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
// To seed and inspect rows that other repositories own.
import 'package:core/src/storage/database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';

/// Only what validation may ask a registered module.
class _Module implements ServiceModule {
  _Module(this.id, ModuleCategory category, {ApiKeyHeader? apiKeyHeader})
    : descriptor = ModuleDescriptor(
        displayName: id,
        icon: const IconData(0),
        category: category,
        authKinds: const [AuthKind.apiKey, AuthKind.userPassword],
        apiKeyHeader: apiKeyHeader ?? const ApiKeyHeader('X-Api-Key'),
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

final _modules = <ServiceModule>[
  _Module('radarr', ModuleCategory.movies),
  _Module('sonarr', ModuleCategory.series),
  _Module('bazarr', ModuleCategory.subtitles),
  _Module(
    'qbittorrent',
    ModuleCategory.downloadClient,
    apiKeyHeader: const ApiKeyHeader('Authorization', prefix: 'Bearer '),
  ),
];

class _SecretStore implements SecretStore {
  final values = <String, String>{};

  /// Each runs before its operation; may throw to make it fail.
  FutureOr<void> Function(String key)? beforeRead;
  FutureOr<void> Function(String key)? beforeWrite;
  void Function(String key)? beforeDelete;

  @override
  Future<String?> read(String key) async {
    await beforeRead?.call(key);
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    beforeDelete?.call(key);
    values.remove(key);
  }
}

// None of these looks like a secret to the log unless it was registered.
const _credential = Credential(
  apiKey: 'zq-alpha-111',
  username: 'zq-bravo-222',
  password: 'zq-charlie-333',
  basicUser: 'zq-delta-444',
  basicPassword: 'zq-echo-555',
  sessionCookie: 'SID=zq-foxtrot-666',
  customHeaders: {'X-Proxy-Id': 'zq-golf-777'},
);

const _secretValues = [
  'zq-alpha-111',
  'zq-bravo-222',
  'zq-charlie-333',
  'zq-delta-444',
  'zq-echo-555',
  'zq-foxtrot-666',
  'zq-golf-777',
];

const _probe = ProbeSnapshot(
  product: 'Radarr',
  version: '5.1.0',
  capabilities: {CapabilityKind.library, CapabilityKind.queue},
);

InstanceDraft _draft({
  String name = 'Movies',
  String serviceType = 'radarr',
  String url = 'https://nas.test:7878/radarr',
  AuthKind authKind = AuthKind.apiKey,
  String? acceptedCertPin,
  bool removeCertPin = false,
  String? customCa,
  ProbeSnapshot? probe,
  bool enabled = true,
  bool authRejected = false,
  List<InstanceLink> links = const [],
}) => InstanceDraft(
  name: name,
  serviceType: serviceType,
  url: Uri.parse(url),
  authKind: authKind,
  acceptedCertPin: acceptedCertPin,
  removeCertPin: removeCertPin,
  customCa: customCa,
  probe: probe,
  enabled: enabled,
  authRejected: authRejected,
  links: links,
);

InstanceLink _link(Instance target) =>
    InstanceLink(type: InstanceLinkType.subtitlesFor, instanceId: target.id);

T _value<T>(Result<T, RuleViolation> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => fail('refused: $error'),
};

void _done(Result<void, RuleViolation> result) {
  if (result case Err(:final error)) fail('refused: $error');
}

RuleViolation? _refusal(Result<Object?, RuleViolation> result) =>
    switch (result) {
      Ok() => null,
      Err(:final error) => error,
    };

Map<String, Object?>? _fields(Credential? credential) => credential == null
    ? null
    : {
        'apiKey': credential.apiKey,
        'username': credential.username,
        'password': credential.password,
        'basicUser': credential.basicUser,
        'basicPassword': credential.basicPassword,
        'sessionCookie': credential.sessionCookie,
        'customHeaders': credential.customHeaders,
      };

/// What [log] shows when something logs the secrets of [_credential].
String _logged(DiagnosticLog log) {
  log.clear();
  log.log(LogLevel.info, 'saw ${_secretValues.join(' and ')}');
  return log.export();
}

void _expectRedacted(String text) {
  expect(text, contains(SecretRedactor.marker));
  for (final secret in _secretValues) {
    expect(text, isNot(contains(secret)));
  }
}

final _uuid = matches(
  RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  ),
);

void main() {
  late AppDatabase database;
  late _SecretStore secrets;
  late DiagnosticLog log;
  late PreferencesRepository preferences;
  late ProfileRepository repository;
  late Profile home;
  late DateTime now;

  ProfileRepository open(AppDatabase database, {DiagnosticLog? withLog}) =>
      ProfileRepository(
        database: database,
        secrets: secrets,
        log: withLog ?? log,
        preferences: PreferencesRepository(database),
        modules: _modules,
        now: () => now,
      );

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    secrets = _SecretStore();
    log = DiagnosticLog();
    preferences = PreferencesRepository(database);
    // Local, so that storing it as it is would show.
    now = DateTime(2026, 1, 2, 3, 4, 5);
    repository = open(database);
    await repository.ensureDefaultProfile();
    home = (await repository.profiles()).single;
  });
  tearDown(() => database.close());

  Future<Instance> add(
    InstanceDraft draft, {
    String? profileId,
    Credential credential = const Credential(),
  }) async => _value(
    await repository.addInstance(
      profileId ?? home.id,
      draft,
      credential: credential,
    ),
  );

  Future<Instance> update(
    Instance instance,
    InstanceDraft draft, {
    Credential? credential,
  }) async => _value(
    await repository.updateInstance(instance.id, draft, credential: credential),
  );

  Future<Instance> stored(Instance instance) async =>
      (await repository.instance(instance.id))!;

  Future<List<String>> profileNames() async => [
    for (final profile in await repository.profiles()) profile.name,
  ];

  Future<String?> activeProfile() async =>
      (await preferences.read()).activeProfileId;

  /// Every value of every row of every table.
  Future<String> databaseText() async {
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final text = StringBuffer();
    for (final table in tables) {
      final rows = await database
          .customSelect('SELECT * FROM "${table.read<String>('name')}"')
          .get();
      for (final row in rows) {
        text.writeln(row.data);
      }
    }
    return text.toString();
  }

  /// Gives [instance] a row in every table that belongs to an instance.
  Future<void> addData(Instance instance) async {
    await database
        .into(database.notificationSubscriptions)
        .insert(
          NotificationSubscriptionsCompanion.insert(
            instanceId: instance.id,
            eventType: 'imported',
            enabled: const Value(true),
          ),
        );
    await database
        .into(database.eventMarkers)
        .insert(
          EventMarkersCompanion.insert(
            instanceId: instance.id,
            eventType: 'imported',
          ),
        );
    await CacheRepository(database)
        .scope(instance.id)
        .replace(MediaKind.movie, [
          CacheEntry(
            instanceId: instance.id,
            kind: MediaKind.movie,
            remoteId: 1,
            sortTitle: 'alien',
            state: ItemState.missing,
            monitored: true,
            rawJson: '{}',
            fetchedAt: now,
          ),
        ]);
    await preferences.saveLastAddChoices(
      instance.id,
      const AddChoices(
        rootFolderId: 1,
        qualityProfileId: 2,
        monitorOptionId: 'movieOnly',
        searchNow: true,
      ),
    );
  }

  Future<List<String>> subscribed() async => [
    for (final row
        in await database.select(database.notificationSubscriptions).get())
      if (row.enabled) row.instanceId,
  ];

  group('first launch', () {
    test('creates one profile, named Default, and makes it active', () async {
      expect(home.name, 'Default');
      expect(home.id, _uuid);
      expect(await activeProfile(), home.id);
    });

    test('creates nothing once a profile exists', () async {
      _done(await repository.renameProfile(home.id, 'Cabin'));

      await repository.ensureDefaultProfile();

      expect(await profileNames(), ['Cabin']);
    });

    test('makes a profile active again if none is', () async {
      await database.delete(database.appPreferences).go();

      await repository.ensureDefaultProfile();

      expect(await activeProfile(), home.id);
      expect(await profileNames(), ['Default']);
    });
  });

  group('profile names', () {
    test('have 1 to 40 characters', () async {
      expect(
        _refusal(await repository.createProfile('')),
        RuleViolation.nameLength,
      );
      expect(
        _refusal(await repository.createProfile('a' * 41)),
        RuleViolation.nameLength,
      );
      expect(
        _refusal(await repository.renameProfile(home.id, 'a' * 41)),
        RuleViolation.nameLength,
      );
      expect(await profileNames(), ['Default']);

      _value(await repository.createProfile('b'));
      _value(await repository.createProfile('c' * 40));
      expect(await profileNames(), ['Default', 'b', 'c' * 40]);
    });

    test('are unique ignoring case, beyond ASCII too', () async {
      final away = _value(await repository.createProfile('Über'));

      expect(
        _refusal(await repository.createProfile('DEFAULT')),
        RuleViolation.nameTaken,
      );
      expect(
        _refusal(await repository.createProfile('über')),
        RuleViolation.nameTaken,
      );
      expect(
        _refusal(await repository.renameProfile(away.id, 'default')),
        RuleViolation.nameTaken,
      );
      expect(
        _refusal(await repository.copyProfile(home.id, name: 'ÜBER')),
        RuleViolation.nameTaken,
      );
      expect(await profileNames(), ['Default', 'Über']);
    });

    test('may change their own case', () async {
      _done(await repository.renameProfile(home.id, 'DEFAULT'));

      expect(await profileNames(), ['DEFAULT']);
    });

    test('change without changing the id or the active profile', () async {
      final away = _value(await repository.createProfile('Away'));
      expect(away.id, _uuid);
      expect(away.id, isNot(home.id));
      expect(away.sortOrder, greaterThan(home.sortOrder));

      _done(await repository.renameProfile(away.id, 'Cabin'));

      expect((await repository.profiles()).last.id, away.id);
      expect(await activeProfile(), home.id);
    });
  });

  group('instances', () {
    test('keep what was saved, with new ids and UTC times', () async {
      final first = await add(
        _draft(customCa: 'ca', acceptedCertPin: 'ab' * 32, probe: _probe),
      );
      final second = await add(
        _draft(name: 'Series', serviceType: 'sonarr', enabled: false),
      );

      final read = await stored(first);
      expect(read.id, _uuid);
      expect(second.id, isNot(first.id));
      expect(read.profileId, home.id);
      expect(read.name, 'Movies');
      expect(read.serviceType, 'radarr');
      expect(read.url, Uri.parse('https://nas.test:7878/radarr'));
      expect(read.authKind, AuthKind.apiKey);
      expect(read.certPin, 'ab' * 32);
      expect(read.customCa, 'ca');
      expect(read.enabled, isTrue);
      expect(read.authFailed, isFalse);
      expect(read.detectedVersion, '5.1.0');
      expect(read.lastProbe!.product, 'Radarr');
      expect(read.lastProbe!.capabilities, _probe.capabilities);
      expect(read.createdAt.isUtc, isTrue);
      expect(read.createdAt.isAtSameMomentAs(now), isTrue);
      expect(read.updatedAt.isUtc, isTrue);
      expect((await stored(second)).enabled, isFalse);
      expect(
        [
          for (final instance in await repository.instances(home.id))
            instance.id,
        ],
        [first.id, second.id],
      );
      expect(second.sortOrder, greaterThan(first.sortOrder));
    });

    test('keep id, profile and creation time when edited', () async {
      final instance = await add(_draft());
      final created = now;
      now = now.add(const Duration(days: 1));

      await update(instance, _draft(name: 'Films'));

      final read = await stored(instance);
      expect(read.name, 'Films');
      expect(read.profileId, home.id);
      expect(read.createdAt.isAtSameMomentAs(created), isTrue);
      expect(read.updatedAt.isAtSameMomentAs(now), isTrue);
      expect(read.updatedAt.isUtc, isTrue);
    });

    test('have names of 1 to 40 characters', () async {
      for (final name in ['', 'a' * 41]) {
        expect(
          _refusal(await repository.addInstance(home.id, _draft(name: name))),
          RuleViolation.nameLength,
        );
      }
      expect(await repository.instances(home.id), isEmpty);

      final instance = await add(_draft(name: 'a' * 40));
      expect(
        _refusal(
          await repository.updateInstance(instance.id, _draft(name: '')),
        ),
        RuleViolation.nameLength,
      );
      expect((await stored(instance)).name, 'a' * 40);
    });

    test('have names unique ignoring case within their profile', () async {
      final movies = await add(_draft());
      final other = await add(_draft(name: 'Other'));

      expect(
        _refusal(
          await repository.addInstance(
            home.id,
            _draft(name: 'MOVIES', serviceType: 'sonarr'),
          ),
        ),
        RuleViolation.nameTaken,
      );
      expect(
        _refusal(
          await repository.updateInstance(other.id, _draft(name: 'movies')),
        ),
        RuleViolation.nameTaken,
      );
      await update(movies, _draft(name: 'movies'));

      final away = _value(await repository.createProfile('Away'));
      await add(_draft(name: 'Movies'), profileId: away.id);
    });

    test('are of a registered service', () async {
      expect(
        _refusal(
          await repository.addInstance(home.id, _draft(serviceType: 'unknown')),
        ),
        RuleViolation.unknownServiceType,
      );
      expect(await repository.instances(home.id), isEmpty);
    });

    test('never change their service', () async {
      final instance = await add(_draft());

      expect(
        _refusal(
          await repository.updateInstance(
            instance.id,
            _draft(serviceType: 'sonarr'),
          ),
        ),
        RuleViolation.serviceTypeChanged,
      );
      expect((await stored(instance)).serviceType, 'radarr');
    });
  });

  group('url', () {
    const accepted = [
      'http://nas.test',
      'https://nas.test',
      'http://192.168.1.10:7878',
      'http://media.example.com/radarr',
      'https://nas.test:8443/apps/radarr/',
      'http://[fd00::1]:7878',
      'HTTP://nas.test',
    ];
    for (final url in accepted) {
      test('may be $url', () async {
        final instance = await add(_draft(url: url));

        expect((await stored(instance)).url, Uri.parse(url));
      });
    }

    const refused = [
      'ftp://nas.test',
      'ws://nas.test',
      'file:///etc/hosts',
      'nas.test',
      'nas.test:7878',
      '/radarr',
      '//nas.test/radarr',
      'http://',
      'http:///radarr',
      'http://nas.test:0',
      'http://nas.test:65536',
      'http://user@nas.test',
      'http://user:pass@nas.test',
      'http://nas.test/radarr?apikey=1',
      'http://nas.test/radarr?',
      'http://nas.test/radarr#section',
      'http://nas.test/radarr#',
    ];
    for (final url in refused) {
      test('may not be $url', () async {
        expect(
          _refusal(await repository.addInstance(home.id, _draft(url: url))),
          RuleViolation.url,
        );
        expect(await repository.instances(home.id), isEmpty);
      });
    }

    test('is checked on edit too', () async {
      final instance = await add(_draft());

      expect(
        _refusal(
          await repository.updateInstance(
            instance.id,
            _draft(url: 'ftp://nas.test'),
          ),
        ),
        RuleViolation.url,
      );
      expect((await stored(instance)).url, instance.url);
    });

    test('changed without a test keeps the capabilities only', () async {
      final instance = await add(_draft(probe: _probe));

      await update(instance, _draft(url: 'https://nas.test:7878/other'));

      final read = await stored(instance);
      expect(read.detectedVersion, isNull);
      expect(read.lastProbe!.capabilities, _probe.capabilities);
    });

    test('unchanged keeps what was detected', () async {
      final instance = await add(_draft(probe: _probe));

      await update(instance, _draft(name: 'Films'));

      final read = await stored(instance);
      expect(read.detectedVersion, '5.1.0');
      expect(read.lastProbe!.capabilities, _probe.capabilities);
    });

    test('changed with a test takes what the test found', () async {
      final instance = await add(_draft(probe: _probe));

      await update(
        instance,
        _draft(
          url: 'https://away.test',
          probe: const ProbeSnapshot(
            product: 'Radarr',
            version: '6.0.0',
            capabilities: {CapabilityKind.library},
          ),
        ),
      );

      final read = await stored(instance);
      expect(read.detectedVersion, '6.0.0');
      expect(read.lastProbe!.capabilities, {CapabilityKind.library});
    });
  });

  group('certificate pin', () {
    final pin = 'ab' * 32;
    final newPin = 'cd' * 32;

    for (final MapEntry(key: change, value: url) in {
      'scheme': 'http://nas.test:7878/radarr',
      'host': 'https://other.test:7878/radarr',
      'port': 'https://nas.test:7879/radarr',
      'port, to the default': 'https://nas.test/radarr',
    }.entries) {
      test('is cleared when the $change changes', () async {
        final instance = await add(_draft(acceptedCertPin: pin));

        await update(instance, _draft(url: url));

        expect((await stored(instance)).certPin, isNull);
      });
    }

    test('is kept when only the path or the name changes', () async {
      final instance = await add(_draft(acceptedCertPin: pin));

      await update(
        instance,
        _draft(name: 'Films', url: 'https://NAS.test:7878/elsewhere'),
      );

      expect((await stored(instance)).certPin, pin);
    });

    test('accepted for the new address is stored', () async {
      final instance = await add(_draft(acceptedCertPin: pin));

      await update(
        instance,
        _draft(url: 'https://other.test', acceptedCertPin: newPin),
      );

      expect((await stored(instance)).certPin, newPin);
    });

    test('is removed on request, at the same address', () async {
      final instance = await add(_draft(acceptedCertPin: pin));

      await update(instance, _draft(removeCertPin: true));

      expect((await stored(instance)).certPin, isNull);
    });

    // The way from an accepted certificate to a private authority.
    test('gives way to an authority at the same address', () async {
      final instance = await add(_draft(acceptedCertPin: pin));

      await update(instance, _draft(removeCertPin: true, customCa: 'ca'));

      final read = await stored(instance);
      expect(read.certPin, isNull);
      expect(read.customCa, 'ca');
    });

    test('accepted now is stored, whatever else is asked', () async {
      final instance = await add(_draft(acceptedCertPin: pin));

      await update(
        instance,
        _draft(acceptedCertPin: newPin, removeCertPin: true),
      );

      expect((await stored(instance)).certPin, newPin);
    });

    test('is not removed by a refused change', () async {
      final instance = await add(_draft(acceptedCertPin: pin));

      final result = await repository.updateInstance(
        instance.id,
        _draft(name: '', removeCertPin: true),
      );

      expect(_refusal(result), RuleViolation.nameLength);
      expect((await stored(instance)).certPin, pin);
    });
  });

  group('custom CA', () {
    test('may be 64 KiB', () async {
      final instance = await add(_draft(customCa: 'a' * 65536));

      expect((await stored(instance)).customCa, hasLength(65536));
    });

    test('may not be larger, counted in bytes', () async {
      // The second is 65,536 characters but one byte more.
      for (final ca in ['a' * 65537, '${'a' * 65535}é']) {
        expect(
          _refusal(await repository.addInstance(home.id, _draft(customCa: ca))),
          RuleViolation.customCaTooLarge,
        );
      }
      final instance = await add(_draft(customCa: 'ca'));
      expect(
        _refusal(
          await repository.updateInstance(
            instance.id,
            _draft(customCa: 'a' * 65537),
          ),
        ),
        RuleViolation.customCaTooLarge,
      );
      expect((await stored(instance)).customCa, 'ca');
    });

    test('is removed by saving none', () async {
      final instance = await add(_draft(customCa: 'ca'));

      await update(instance, _draft());

      expect((await stored(instance)).customCa, isNull);
    });
  });

  group('custom headers', () {
    Credential headers(String name) =>
        Credential(customHeaders: {name: 'value'});

    for (final name in [
      'X-Proxy-Id',
      'Authorization',
      'x_1',
      "!#\$%&'*+-.^_`|~",
    ]) {
      test('may be named $name', () async {
        final instance = await add(_draft(), credential: headers(name));

        expect((await repository.credential(instance.id))!.customHeaders, {
          name: 'value',
        });
      });
    }

    for (final name in [
      '',
      'X Proxy',
      'X-Proxy:',
      'X(Proxy)',
      'X/Proxy',
      'X-Prôxy',
      'X-Proxy\r\nEvil',
      'X-Proxy\n',
      'Host',
      'hOST',
      'Content-Length',
      'content-length',
    ]) {
      test('may not be named ${Uri.encodeComponent(name)}', () async {
        expect(
          _refusal(
            await repository.addInstance(
              home.id,
              _draft(),
              credential: headers(name),
            ),
          ),
          RuleViolation.headerName,
        );
        expect(await repository.instances(home.id), isEmpty);
        expect(secrets.values, isEmpty);
      });
    }

    test('are checked on edit too', () async {
      final instance = await add(_draft(), credential: _credential);

      expect(
        _refusal(
          await repository.updateInstance(
            instance.id,
            _draft(name: 'Films'),
            credential: headers('Host'),
          ),
        ),
        RuleViolation.headerName,
      );
      expect((await stored(instance)).name, 'Movies');
      expect(
        _fields(await repository.credential(instance.id)),
        _fields(_credential),
      );
    });
  });

  group('basic authentication', () {
    const both = Credential(
      apiKey: 'zq-alpha-111',
      basicUser: 'zq-delta-444',
      basicPassword: 'zq-echo-555',
    );

    test('is refused with an API key sent in Authorization', () async {
      expect(
        _refusal(
          await repository.addInstance(
            home.id,
            _draft(serviceType: 'qbittorrent'),
            credential: both,
          ),
        ),
        RuleViolation.basicAuthWithApiKey,
      );
      final instance = await add(
        _draft(serviceType: 'qbittorrent'),
        credential: const Credential(apiKey: 'zq-alpha-111'),
      );
      expect(
        _refusal(
          await repository.updateInstance(
            instance.id,
            _draft(serviceType: 'qbittorrent'),
            credential: both,
          ),
        ),
        RuleViolation.basicAuthWithApiKey,
      );
    });

    test('is allowed with a password login there', () async {
      await add(
        _draft(serviceType: 'qbittorrent', authKind: AuthKind.userPassword),
        credential: const Credential(
          username: 'zq-bravo-222',
          password: 'zq-charlie-333',
          basicUser: 'zq-delta-444',
          basicPassword: 'zq-echo-555',
        ),
      );
    });

    test('is allowed with an API key in another header', () async {
      await add(_draft(), credential: both);
    });

    test('kept from a password login refuses a change to an API key', () async {
      final instance = await add(
        _draft(serviceType: 'qbittorrent', authKind: AuthKind.userPassword),
        credential: both,
      );

      expect(
        _refusal(
          await repository.updateInstance(
            instance.id,
            _draft(serviceType: 'qbittorrent'),
          ),
        ),
        RuleViolation.basicAuthWithApiKey,
      );
      expect((await stored(instance)).authKind, AuthKind.userPassword);
    });
  });

  group('links', () {
    late Instance movies;
    late Instance series;

    setUp(() async {
      movies = await add(_draft());
      series = await add(_draft(name: 'Series', serviceType: 'sonarr'));
    });

    InstanceDraft subtitles(List<Instance> targets) => _draft(
      name: 'Subtitles',
      serviceType: 'bazarr',
      links: [for (final target in targets) _link(target)],
    );

    Future<List<String>> targets(Instance instance) async => [
      for (final link in (await stored(instance)).links) link.instanceId,
    ];

    test('go to one movie and one series instance', () async {
      final instance = await add(subtitles([movies, series]));

      expect(await targets(instance), unorderedEquals([movies.id, series.id]));

      await update(instance, subtitles([series]));
      expect(await targets(instance), [series.id]);
    });

    test('are refused otherwise', () async {
      final more = await add(_draft(name: 'More movies'));
      final client = await add(
        _draft(name: 'Client', serviceType: 'qbittorrent'),
      );
      final away = _value(await repository.createProfile('Away'));
      final elsewhere = await add(_draft(), profileId: away.id);

      for (final MapEntry(key: reason, value: draft) in {
        'two movie instances': subtitles([movies, more]),
        'a download client': subtitles([client]),
        'another profile': subtitles([elsewhere]),
        'not from subtitles': _draft(
          name: 'Not subtitles',
          links: [_link(series)],
        ),
        'no such instance': _draft(
          name: 'Nowhere',
          serviceType: 'bazarr',
          links: const [
            InstanceLink(
              type: InstanceLinkType.subtitlesFor,
              instanceId: 'missing',
            ),
          ],
        ),
      }.entries) {
        expect(
          _refusal(await repository.addInstance(home.id, draft)),
          RuleViolation.link,
          reason: reason,
        );
      }

      final instance = await add(subtitles([movies]));
      expect(
        _refusal(
          await repository.updateInstance(
            instance.id,
            subtitles([movies, more]),
          ),
        ),
        RuleViolation.link,
      );
      expect(await targets(instance), [movies.id]);
    });

    test('go with a deleted target', () async {
      final instance = await add(subtitles([movies, series]));

      await repository.deleteInstance(movies.id);

      expect(await targets(instance), [series.id]);
    });
  });

  group('credentials', () {
    test('are stored under cred/<instanceId>, not in the database', () async {
      final instance = await add(_draft(), credential: _credential);

      expect(secrets.values.keys, ['cred/${instance.id}']);
      expect(
        _fields(await repository.credential(instance.id)),
        _fields(_credential),
      );
      final text = await databaseText();
      for (final secret in _secretValues) {
        expect(text, isNot(contains(secret)));
      }
    });

    test('survive reopening', () async {
      final instance = await add(_draft(), credential: _credential);

      expect(
        _fields(await open(database).credential(instance.id)),
        _fields(_credential),
      );
    });

    test('are kept when saved without new ones', () async {
      final instance = await add(_draft(), credential: _credential);

      await update(instance, _draft(name: 'Films'));

      expect(
        _fields(await repository.credential(instance.id)),
        _fields(_credential),
      );
    });

    test('are replaced as a whole by new ones', () async {
      final instance = await add(_draft(), credential: _credential);
      const replacement = Credential(apiKey: 'zq-hotel-888');

      await update(instance, _draft(), credential: replacement);

      expect(
        _fields(await repository.credential(instance.id)),
        _fields(replacement),
      );
    });

    test('are kept when the url changes, but not the session', () async {
      final instance = await add(_draft(), credential: _credential);

      await update(instance, _draft(url: 'https://other.test/radarr'));

      expect(_fields(await repository.credential(instance.id)), {
        ..._fields(_credential)!,
        'sessionCookie': null,
      });
    });

    test('lose the old session when saved with a new url', () async {
      final instance = await add(_draft(), credential: _credential);

      await update(
        instance,
        _draft(url: 'http://nas.test:7878/radarr'),
        credential: _credential,
      );

      expect((await repository.credential(instance.id))!.sessionCookie, isNull);
    });

    test('keep the session when only the path changes', () async {
      final instance = await add(_draft(), credential: _credential);

      await update(instance, _draft(url: 'https://nas.test:7878/other'));

      expect(
        (await repository.credential(instance.id))!.sessionCookie,
        _credential.sessionCookie,
      );
    });

    test('that cannot be stored leave no instance', () async {
      secrets.beforeWrite = (_) => throw const FileSystemException('locked');

      await expectLater(
        repository.addInstance(home.id, _draft(), credential: _credential),
        throwsA(isA<FileSystemException>()),
      );

      expect(await repository.instances(home.id), isEmpty);
    });
  });

  group('the log knows the credentials', () {
    test('before they are stored, when added', () async {
      final seen = <String>[];
      secrets.beforeWrite = (_) => seen.add(_logged(log));

      await add(_draft(), credential: _credential);

      expect(seen, isNotEmpty);
      seen.forEach(_expectRedacted);
    });

    test('before they are stored, when edited', () async {
      final instance = await add(_draft());
      final seen = <String>[];
      secrets.beforeWrite = (_) => seen.add(_logged(log));

      await update(instance, _draft(), credential: _credential);

      expect(seen, isNotEmpty);
      seen.forEach(_expectRedacted);
    });

    test('even if they are refused', () async {
      expect(
        _refusal(
          await repository.addInstance(
            home.id,
            _draft(name: ''),
            credential: _credential,
          ),
        ),
        RuleViolation.nameLength,
      );

      _expectRedacted(_logged(log));
    });

    test('once they are read', () async {
      final instance = await add(_draft(), credential: _credential);
      final fresh = DiagnosticLog();

      await open(database, withLog: fresh).credential(instance.id);

      _expectRedacted(_logged(fresh));
    });

    test('once they are copied', () async {
      await add(_draft(), credential: _credential);
      final fresh = DiagnosticLog();
      final seen = <String>[];
      secrets.beforeWrite = (_) => seen.add(_logged(fresh));

      _value(
        await open(database, withLog: fresh).copyProfile(home.id, name: 'Away'),
      );

      expect(seen, isNotEmpty);
      seen.forEach(_expectRedacted);
    });
  });

  group('a secret store that fails', () {
    Never locked(String key) => throw const FileSystemException('locked');
    final throwsLocked = throwsA(isA<FileSystemException>());

    late Instance instance;

    setUp(() async {
      instance = await add(_draft(), credential: _credential);
      await repository.markAuthFailed(instance.id);
    });

    test('to read lets the caller know', () async {
      secrets.beforeRead = locked;

      await expectLater(repository.credential(instance.id), throwsLocked);
    });

    test('to read does not stop edits that keep the session', () async {
      secrets.beforeRead = locked;

      await update(instance, _draft(name: 'Films'));

      expect((await stored(instance)).name, 'Films');
    });

    test('to read stops a new origin from getting the old session', () async {
      secrets.beforeRead = locked;

      await expectLater(
        repository.updateInstance(
          instance.id,
          _draft(url: 'https://other.test'),
        ),
        throwsLocked,
      );

      expect((await stored(instance)).url, instance.url);
    });

    test('to read still takes new credentials', () async {
      secrets.beforeRead = locked;

      await update(
        instance,
        _draft(url: 'https://other.test'),
        credential: _credential,
      );

      secrets.beforeRead = null;
      expect(_fields(await repository.credential(instance.id)), {
        ..._fields(_credential)!,
        'sessionCookie': null,
      });
      expect((await stored(instance)).authFailed, isFalse);
    });

    test('to read lets a profile be neither copied nor half copied', () async {
      final rows = await databaseText();
      secrets.beforeRead = locked;

      await expectLater(
        repository.copyProfile(home.id, name: 'Away'),
        throwsLocked,
      );

      expect(await databaseText(), rows);
      expect(secrets.values.keys, ['cred/${instance.id}']);
    });

    test('to write keeps the record and the old credential', () async {
      final rows = await databaseText();
      // Fails once, having removed the old value as the store may.
      secrets.beforeWrite = (key) {
        secrets.beforeWrite = null;
        secrets.values.remove(key);
        locked(key);
      };

      await expectLater(
        repository.updateInstance(
          instance.id,
          _draft(url: 'https://other.test'),
          credential: const Credential(apiKey: 'zq-hotel-888'),
        ),
        throwsLocked,
      );

      expect(await databaseText(), rows);
      expect(
        _fields(await repository.credential(instance.id)),
        _fields(_credential),
      );
    });

    test('to write and to delete reports the write', () async {
      secrets.beforeWrite = locked;
      secrets.beforeDelete = (_) => throw StateError('broken');

      await expectLater(
        repository.addInstance(
          home.id,
          _draft(name: 'Other'),
          credential: _credential,
        ),
        throwsLocked,
      );

      expect(await repository.instances(home.id), hasLength(1));
    });

    test('to delete does not keep an instance', () async {
      await addData(instance);
      secrets.beforeDelete = locked;
      log.clear();

      await repository.deleteInstance(instance.id);

      expect(await repository.instances(home.id), isEmpty);
      expect(await subscribed(), isEmpty);
      expect(log.entries.single.level, LogLevel.warning);
    });

    test('to delete does not keep a profile', () async {
      final away = _value(await repository.createProfile('Away'));
      await add(_draft(), profileId: away.id, credential: _credential);
      await add(
        _draft(name: 'Other'),
        profileId: away.id,
        credential: _credential,
      );
      final tried = <String>[];
      secrets.beforeDelete = (key) {
        tried.add(key);
        locked(key);
      };

      _done(await repository.deleteProfile(away.id));

      expect(await profileNames(), ['Default']);
      // Each secret is tried, whatever the earlier ones did.
      expect(tried, hasLength(2));
    });

    test('by holding something else reads as no credential', () async {
      secrets.values['cred/${instance.id}'] = '{"apiKey": "zq-alpha-1';

      expect(await repository.credential(instance.id), isNull);
    });
  });

  group('erasing secrets', () {
    late Instance movies;
    late Instance other;

    setUp(() async {
      movies = await add(_draft(), credential: _credential);
      other = await add(_draft(name: 'Other'), credential: _credential);
    });

    Future<List<String>> pending() async => [
      for (final row
          in await database.select(database.pendingSecretDeletions).get())
        row.secretKey,
    ];

    /// Makes the database refuse to delete from [table].
    Future<void> refuseDelete(String table) => database.customStatement(
      'CREATE TRIGGER refuse BEFORE DELETE ON $table '
      "BEGIN SELECT RAISE(ABORT, 'refused'); END",
    );

    void locked(String key) => throw const FileSystemException('locked');

    test('waits until an instance is really deleted', () async {
      await refuseDelete('instances');

      await expectLater(
        repository.deleteInstance(movies.id),
        throwsA(anything),
      );

      expect(await repository.instance(movies.id), isNotNull);
      expect(
        _fields(await repository.credential(movies.id)),
        _fields(_credential),
      );
      expect(await pending(), isEmpty);
    });

    test('waits until a profile is really deleted', () async {
      _value(await repository.createProfile('Away'));
      await refuseDelete('profiles');

      await expectLater(repository.deleteProfile(home.id), throwsA(anything));

      expect(secrets.values, hasLength(2));
      expect(await pending(), isEmpty);
    });

    test('that fails is done at a later launch', () async {
      secrets.beforeDelete = locked;
      await repository.deleteInstance(movies.id);
      expect(await pending(), ['cred/${movies.id}']);

      // A launch at which the store still fails.
      await open(database).ensureDefaultProfile();
      expect(secrets.values, hasLength(2));
      expect(await pending(), ['cred/${movies.id}']);

      secrets.beforeDelete = null;
      await open(database).ensureDefaultProfile();

      expect(secrets.values.keys, ['cred/${other.id}']);
      expect(await pending(), isEmpty);
    });

    test('of a deleted profile is retried too', () async {
      _value(await repository.createProfile('Away'));
      secrets.beforeDelete = locked;
      _done(await repository.deleteProfile(home.id));
      expect(
        await pending(),
        unorderedEquals(['cred/${movies.id}', 'cred/${other.id}']),
      );

      secrets.beforeDelete = null;
      await repository.ensureDefaultProfile();

      expect(secrets.values, isEmpty);
      expect(await pending(), isEmpty);
    });

    test('never takes the secret of an instance that exists', () async {
      // As if an instance had been restored with the id of a deleted one.
      await database
          .into(database.pendingSecretDeletions)
          .insert(
            PendingSecretDeletionsCompanion.insert(
              secretKey: 'cred/${movies.id}',
            ),
          );

      await repository.ensureDefaultProfile();

      expect(
        _fields(await repository.credential(movies.id)),
        _fields(_credential),
      );
      expect(await pending(), isEmpty);
    });

    test('left by a failed copy is done at a later launch', () async {
      var writes = 0;
      secrets.beforeWrite = (key) {
        if (++writes == 2) locked(key);
      };
      secrets.beforeDelete = locked;
      await expectLater(
        repository.copyProfile(home.id, name: 'Away'),
        throwsA(isA<FileSystemException>()),
      );
      expect(secrets.values, hasLength(3));

      secrets.beforeDelete = null;
      await repository.ensureDefaultProfile();

      expect(
        secrets.values.keys,
        unorderedEquals(['cred/${movies.id}', 'cred/${other.id}']),
      );
      expect(await pending(), isEmpty);
    });
  });

  group('changes made at the same time', () {
    late Instance instance;

    setUp(() async {
      instance = await add(_draft(), credential: _credential);
    });

    Future<void> pause() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test('do not run while a failed one is being undone', () async {
      await database.customStatement(
        'CREATE TRIGGER refuse BEFORE UPDATE ON instances '
        "WHEN new.name = 'Refused' "
        "BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );
      var writes = 0;
      // The second write puts the old session back; make that slow.
      secrets.beforeWrite = (_) => ++writes == 2 ? pause() : null;

      final failing = expectLater(
        repository.updateInstance(
          instance.id,
          _draft(name: 'Refused', url: 'https://first.test'),
        ),
        throwsA(anything),
      );
      final queued = update(instance, _draft(url: 'https://second.test'));
      await Future.wait([failing, queued]);

      expect((await stored(instance)).url, Uri.parse('https://second.test'));
      expect((await repository.credential(instance.id))!.sessionCookie, isNull);
    });

    test('do not come between an instance and its credential', () async {
      secrets.beforeRead = (_) {
        secrets.beforeRead = null;
        return pause();
      };

      final read = repository.instanceWithCredential(instance.id);
      final edit = update(
        instance,
        _draft(url: 'https://other.test'),
        credential: const Credential(apiKey: 'zq-hotel-888'),
      );

      final before = (await read)!;
      expect(before.instance.url, instance.url);
      expect(_fields(before.credential), _fields(_credential));

      await edit;
      final after = (await repository.instanceWithCredential(instance.id))!;
      expect(after.instance.url, Uri.parse('https://other.test'));
      expect(after.credential!.apiKey, 'zq-hotel-888');
    });

    test('leave nothing to read of a deleted instance', () async {
      await repository.deleteInstance(instance.id);

      expect(await repository.instanceWithCredential(instance.id), isNull);
    });
  });

  group('the authFailed latch', () {
    late Instance instance;

    setUp(() async {
      instance = await add(_draft(), credential: _credential);
      await repository.markAuthFailed(instance.id);
    });

    Future<bool> latched() async => (await stored(instance)).authFailed;

    test('is set for that instance only', () async {
      final other = await add(_draft(name: 'Other'));

      expect(await latched(), isTrue);
      expect((await stored(other)).authFailed, isFalse);
    });

    test('is cleared when the user retries', () async {
      await repository.retryAuth(instance.id);

      expect(await latched(), isFalse);
    });

    test('stays through edits that leave the credentials', () async {
      await update(instance, _draft(name: 'Films', enabled: false));
      await update(instance, _draft(url: 'https://other.test', probe: _probe));

      expect(await latched(), isTrue);
    });

    test('is set by adding a draft whose test was refused', () async {
      final added = await add(
        _draft(name: 'Other', authRejected: true),
        credential: _credential,
      );

      expect(added.authFailed, isTrue);
    });

    test('is set again when refused new credentials are saved', () async {
      await update(
        instance,
        _draft(authRejected: true),
        credential: const Credential(apiKey: 'zq-hotel-888'),
      );

      expect(await latched(), isTrue);
    });

    test('stays when the same credentials are saved again', () async {
      await update(instance, _draft(), credential: _credential);

      expect(await latched(), isTrue);
    });

    for (final MapEntry(key: field, value: edited) in {
      'API key': const Credential(apiKey: 'zq-hotel-888'),
      'password': const Credential(
        apiKey: 'zq-alpha-111',
        username: 'zq-bravo-222',
        password: 'zq-hotel-888',
        basicUser: 'zq-delta-444',
        basicPassword: 'zq-echo-555',
        sessionCookie: 'SID=zq-foxtrot-666',
        customHeaders: {'X-Proxy-Id': 'zq-golf-777'},
      ),
      'custom header': const Credential(
        apiKey: 'zq-alpha-111',
        username: 'zq-bravo-222',
        password: 'zq-charlie-333',
        basicUser: 'zq-delta-444',
        basicPassword: 'zq-echo-555',
        sessionCookie: 'SID=zq-foxtrot-666',
        customHeaders: {'X-Proxy-Id': 'zq-hotel-888'},
      ),
    }.entries) {
      test('is cleared by editing the $field', () async {
        await update(instance, _draft(), credential: edited);

        expect(await latched(), isFalse);
      });
    }

    test('stays when a refused edit carried new credentials', () async {
      expect(
        _refusal(
          await repository.updateInstance(
            instance.id,
            _draft(name: ''),
            credential: const Credential(apiKey: 'zq-hotel-888'),
          ),
        ),
        RuleViolation.nameLength,
      );

      expect(await latched(), isTrue);
    });

    test('is persisted', () async {
      final directory = await Directory.systemTemp.createTemp('instances');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/app.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      final writer = open(first);
      await writer.ensureDefaultProfile();
      final profile = (await writer.profiles()).single;
      final added = _value(await writer.addInstance(profile.id, _draft()));
      await writer.markAuthFailed(added.id);
      await first.close();

      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);

      expect((await open(second).instance(added.id))!.authFailed, isTrue);
    });
  });

  group('deleting an instance', () {
    late Instance movies;
    late Instance other;

    setUp(() async {
      movies = await add(_draft(), credential: _credential);
      other = await add(_draft(name: 'Other'), credential: _credential);
      await addData(movies);
      await addData(other);
      await preferences.saveView(
        home.id,
        MediaKind.movie,
        LibraryView(
          instanceScope: movies.id,
          filters: LibraryFilters(
            tags: {
              InstanceOptionId(movies.id, 1),
              InstanceOptionId(other.id, 1),
            },
          ),
        ),
      );
    });

    test('removes it with its secrets and data, and no other', () async {
      await repository.deleteInstance(movies.id);

      expect(await repository.instance(movies.id), isNull);
      expect(secrets.values.keys, ['cred/${other.id}']);
      expect(await subscribed(), [other.id]);
      expect(await preferences.lastAddChoices(movies.id), isNull);
      expect(await preferences.lastAddChoices(other.id), isNotNull);
      expect(
        await CacheRepository(database).scope(other.id).read(MediaKind.movie),
        isNotNull,
      );
      // Its id is gone from every table, the columns of stored views included.
      final text = await databaseText();
      expect(text, isNot(contains(movies.id)));
      expect(text, contains(other.id));
    });

    test('leaves the rest of the stored views', () async {
      await repository.deleteInstance(movies.id);

      final view = await preferences.view(home.id, MediaKind.movie);
      expect(view.instanceScope, isNull);
      expect(view.filters.tags, {InstanceOptionId(other.id, 1)});
    });
  });

  group('reordering instances', () {
    late Instance a;
    late Instance b;
    late Instance c;

    setUp(() async {
      a = await add(_draft(name: 'A'));
      b = await add(_draft(name: 'B'));
      c = await add(_draft(name: 'C'));
    });

    Future<List<String>> names([String? profileId]) async => [
      for (final instance in await repository.instances(profileId ?? home.id))
        instance.name,
    ];

    test('stores the order given', () async {
      await repository.reorderInstances(home.id, [c.id, a.id, b.id]);

      expect(await names(), ['C', 'A', 'B']);
    });

    test('is not an edit, and later instances still go last', () async {
      now = DateTime(2027);

      await repository.reorderInstances(home.id, [c.id, b.id, a.id]);
      await add(_draft(name: 'D'));

      for (final instance in [a, b, c]) {
        expect((await stored(instance)).updatedAt, instance.updatedAt);
      }
      expect(await names(), ['C', 'B', 'A', 'D']);
    });

    test('puts those not named after the others, as they were', () async {
      await repository.reorderInstances(home.id, [c.id]);

      expect(await names(), ['C', 'A', 'B']);
    });

    test('ignores ids of another profile, of none, and repeats', () async {
      final away = _value(await repository.createProfile('Away'));
      final x = await add(_draft(name: 'X'), profileId: away.id);

      await repository.reorderInstances(home.id, [
        x.id,
        'none',
        b.id,
        b.id,
        a.id,
      ]);

      expect(await names(), ['B', 'A', 'C']);
      expect((await stored(x)).sortOrder, x.sortOrder);
    });

    test('works beside a row that cannot be read', () async {
      await database.customStatement(
        "UPDATE instances SET auth_kind = 'other' WHERE id = '${b.id}'",
      );

      await repository.reorderInstances(home.id, [c.id, a.id]);

      expect(await names(), ['C', 'A']);
    });

    test('of a profile that does not exist is an error', () async {
      await expectLater(
        repository.reorderInstances('none', [a.id]),
        throwsArgumentError,
      );
    });
  });

  group('copying a profile', () {
    late Instance movies;
    late Instance series;
    late Instance subtitles;
    late Profile copy;
    late Map<String, Instance> copies;

    setUp(() async {
      movies = await add(
        _draft(
          acceptedCertPin: 'ab' * 32,
          customCa: 'ca',
          probe: _probe,
          enabled: false,
        ),
        credential: _credential,
      );
      series = await add(
        _draft(name: 'Series', serviceType: 'sonarr'),
        credential: const Credential(apiKey: 'zq-hotel-888'),
      );
      subtitles = await add(
        _draft(
          name: 'Subtitles',
          serviceType: 'bazarr',
          links: [_link(movies), _link(series)],
        ),
      );
      await repository.markAuthFailed(series.id);
      await addData(movies);
      await preferences.saveView(
        home.id,
        MediaKind.movie,
        LibraryView(
          layout: LibraryLayout.list,
          instanceScope: movies.id,
          filters: LibraryFilters(
            qualityProfiles: {InstanceOptionId(movies.id, 4)},
          ),
        ),
      );

      copy = _value(await repository.copyProfile(home.id, name: 'Away'));
      copies = {
        for (final instance in await repository.instances(copy.id))
          instance.name: instance,
      };
    });

    test('creates new ids and leaves the original', () async {
      expect(await profileNames(), ['Default', 'Away']);
      expect(copy.id, _uuid);
      expect(copy.id, isNot(home.id));
      expect(await activeProfile(), home.id);
      expect(
        [
          for (final instance in await repository.instances(copy.id))
            instance.name,
        ],
        ['Movies', 'Series', 'Subtitles'],
      );
      final originals = [movies.id, series.id, subtitles.id];
      expect([
        for (final instance in await repository.instances(home.id)) instance.id,
      ], originals);
      for (final instance in copies.values) {
        expect(instance.id, _uuid);
        expect(originals, isNot(contains(instance.id)));
        expect(instance.profileId, copy.id);
      }
    });

    test('copies the records', () async {
      final read = copies['Movies']!;

      expect(read.serviceType, 'radarr');
      expect(read.url, movies.url);
      expect(read.authKind, AuthKind.apiKey);
      expect(read.certPin, 'ab' * 32);
      expect(read.customCa, 'ca');
      expect(read.enabled, isFalse);
      expect(read.detectedVersion, '5.1.0');
      expect(read.lastProbe!.capabilities, _probe.capabilities);
      expect(read.authFailed, isFalse);
      // Rejected credentials stay rejected in the copy.
      expect(copies['Series']!.authFailed, isTrue);
    });

    test('copies the credentials', () async {
      final id = copies['Movies']!.id;

      expect(secrets.values.keys, contains('cred/$id'));
      expect(_fields(await repository.credential(id)), _fields(_credential));
      expect(
        (await repository.credential(copies['Series']!.id))!.apiKey,
        'zq-hotel-888',
      );
    });

    test('remaps the links to the copies', () async {
      expect([
        for (final link in copies['Subtitles']!.links) link.instanceId,
      ], unorderedEquals([copies['Movies']!.id, copies['Series']!.id]));
      expect([
        for (final link in (await stored(subtitles)).links) link.instanceId,
      ], unorderedEquals([movies.id, series.id]));
    });

    test('copies the views with the ids remapped', () async {
      final view = await preferences.view(copy.id, MediaKind.movie);
      final id = copies['Movies']!.id;

      expect(view.layout, LibraryLayout.list);
      expect(view.instanceScope, id);
      expect(view.filters.qualityProfiles, {InstanceOptionId(id, 4)});
      expect(
        (await preferences.view(home.id, MediaKind.movie)).instanceScope,
        movies.id,
      );
    });

    test('copies the subscriptions, not caches or markers', () async {
      final id = copies['Movies']!.id;

      expect(await subscribed(), unorderedEquals([movies.id, id]));
      expect(
        await CacheRepository(database).scope(id).read(MediaKind.movie),
        isNull,
      );
      expect(
        [
          for (final row in await database.select(database.eventMarkers).get())
            row.instanceId,
        ],
        [movies.id],
      );
    });

    test('makes copies that are independent', () async {
      await repository.deleteInstance(copies['Movies']!.id);

      expect(
        _fields(await repository.credential(movies.id)),
        _fields(_credential),
      );
      expect((await stored(subtitles)).links, hasLength(2));
    });

    test('leaves nothing behind if a secret cannot be stored', () async {
      final keys = secrets.values.keys.toSet();
      final rows = await databaseText();
      var writes = 0;
      secrets.beforeWrite = (_) {
        if (++writes == 2) throw const FileSystemException('locked');
      };

      await expectLater(
        repository.copyProfile(home.id, name: 'Cabin'),
        throwsA(isA<FileSystemException>()),
      );

      expect(secrets.values.keys.toSet(), keys);
      expect(await databaseText(), rows);
    });
  });

  group('deleting a profile', () {
    late Profile away;
    late Instance kept;
    late Instance movies;
    late Instance series;

    setUp(() async {
      away = _value(await repository.createProfile('Away'));
      kept = await add(_draft(), credential: _credential);
      movies = await add(_draft(), profileId: away.id, credential: _credential);
      series = await add(
        _draft(name: 'Series', serviceType: 'sonarr'),
        profileId: away.id,
        credential: _credential,
      );
      await addData(kept);
      await addData(movies);
      await addData(series);
      await preferences.saveView(
        away.id,
        MediaKind.movie,
        LibraryView(instanceScope: movies.id),
      );
    });

    test('removes its instances, secrets and data, and no other', () async {
      _done(await repository.deleteProfile(away.id));

      expect(await profileNames(), ['Default']);
      expect(secrets.values.keys, ['cred/${kept.id}']);
      expect(await subscribed(), [kept.id]);
      final text = await databaseText();
      for (final id in [away.id, movies.id, series.id]) {
        expect(text, isNot(contains(id)));
      }
      expect(text, contains(kept.id));
    });

    test('that is not active keeps the active one', () async {
      _done(await repository.deleteProfile(away.id));

      expect(await activeProfile(), home.id);
    });

    test('that is active activates another', () async {
      _done(await repository.deleteProfile(home.id));

      expect(await activeProfile(), away.id);
    });

    test('is refused for the last one', () async {
      _done(await repository.deleteProfile(away.id));

      expect(
        _refusal(await repository.deleteProfile(home.id)),
        RuleViolation.lastProfile,
      );

      expect(await profileNames(), ['Default']);
      expect(await activeProfile(), home.id);
      expect(await repository.instance(kept.id), isNotNull);
      expect(secrets.values.keys, ['cred/${kept.id}']);
      expect(await subscribed(), [kept.id]);
    });
  });
}
