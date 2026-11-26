import 'package:core/src/instances/auth_kind.dart';
import 'package:core/src/instances/instance_link_type.dart';
import 'package:core/src/models/item_state.dart';
import 'package:core/src/models/media_kind.dart';
import 'package:core/src/storage/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

// Generated from drift_schemas/ by .github/scripts/codegen.sh.
import 'generated/schema.dart';

final _time = DateTime.utc(2026, 1, 2, 3, 4, 5, 6);

AppDatabase _inMemory() => AppDatabase(NativeDatabase.memory());

void main() {
  group('migrations', () {
    final verifier = SchemaVerifier(GeneratedHelper());

    // Fails when the tables change without a new version and exported schema.
    final current = GeneratedHelper.versions.last;

    test('a new database has the newest exported schema', () async {
      final database = _inMemory();
      addTearDown(database.close);

      expect(database.schemaVersion, current);
      await verifier.migrateAndValidate(database, current);
    });

    test('every exported version opens as the current schema', () async {
      for (final version in GeneratedHelper.versions) {
        final database = AppDatabase(await verifier.startAt(version));
        await verifier.migrateAndValidate(database, current);
        await database.close();
      }
    });
  });

  group('rows', () {
    late AppDatabase database;

    setUp(() => database = _inMemory());
    tearDown(() => database.close());

    Future<void> addProfile(String id) => database
        .into(database.profiles)
        .insert(ProfilesCompanion.insert(id: id, name: id));

    Future<void> addInstance(String id, {String profileId = 'home'}) => database
        .into(database.instances)
        .insert(
          InstancesCompanion.insert(
            id: id,
            profileId: profileId,
            name: id,
            serviceType: 'radarr',
            url: 'http://nas.test/radarr',
            authKind: AuthKind.apiKey,
            createdAt: _time,
            updatedAt: _time,
          ),
        );

    /// One row in every table that belongs to an instance or a profile.
    Future<void> addEverything() async {
      await addProfile('home');
      await addInstance('movies');
      await addInstance('subtitles');
      await database
          .into(database.instanceLinks)
          .insert(
            InstanceLinksCompanion.insert(
              instanceId: 'subtitles',
              type: InstanceLinkType.subtitlesFor,
              targetInstanceId: 'movies',
            ),
          );
      await database
          .into(database.appPreferences)
          .insert(
            AppPreferencesCompanion.insert(
              activeProfileId: const Value('home'),
            ),
          );
      await database
          .into(database.viewPreferences)
          .insert(
            ViewPreferencesCompanion.insert(
              profileId: 'home',
              library: 'movies',
              layout: 'grid',
              sort: 'title',
              filters: '{}',
            ),
          );
      await database
          .into(database.lastAddChoices)
          .insert(
            LastAddChoicesCompanion.insert(instanceId: 'movies', choices: '{}'),
          );
      await database
          .into(database.notificationSubscriptions)
          .insert(
            NotificationSubscriptionsCompanion.insert(
              instanceId: 'movies',
              eventType: 'imported',
            ),
          );
      await database
          .into(database.eventMarkers)
          .insert(
            EventMarkersCompanion.insert(
              instanceId: 'movies',
              eventType: 'imported',
            ),
          );
      await database
          .into(database.cacheEntries)
          .insert(
            CacheEntriesCompanion.insert(
              instanceId: 'movies',
              kind: MediaKind.movie,
              remoteId: 7,
              sortTitle: 'alpha',
              state: ItemState.missing,
              monitored: true,
              tagIds: [3, 5],
              rawJson: '{"id":7}',
              fetchedAt: _time,
            ),
          );
      await database
          .into(database.cacheFetches)
          .insert(
            CacheFetchesCompanion.insert(
              instanceId: 'movies',
              kind: MediaKind.movie,
              parentRemoteId: CacheFetches.noParent,
              fetchedAt: _time,
            ),
          );
    }

    Future<int> count(TableInfo<Table, Object?> table) async =>
        (await database.select(table).get()).length;

    test('keep enum names, tag lists and UTC times', () async {
      await addEverything();

      final entry = await database.select(database.cacheEntries).getSingle();
      expect(entry.kind, MediaKind.movie);
      expect(entry.state, ItemState.missing);
      expect(entry.tagIds, [3, 5]);
      expect(entry.fetchedAt, _time);
      expect(entry.fetchedAt.isUtc, isTrue);
    });

    test('are deleted with their instance', () async {
      await addEverything();

      await (database.delete(
        database.instances,
      )..where((row) => row.id.equals('movies'))).go();

      expect(await count(database.instances), 1);
      expect(await count(database.instanceLinks), 0);
      expect(await count(database.lastAddChoices), 0);
      expect(await count(database.notificationSubscriptions), 0);
      expect(await count(database.eventMarkers), 0);
      expect(await count(database.cacheEntries), 0);
      expect(await count(database.cacheFetches), 0);
    });

    test('are deleted with their profile', () async {
      await addEverything();

      await database.delete(database.profiles).go();

      expect(await count(database.instances), 0);
      expect(await count(database.viewPreferences), 0);
      expect(await count(database.cacheEntries), 0);
      final preferences = await database
          .select(database.appPreferences)
          .getSingle();
      expect(preferences.activeProfileId, isNull);
    });

    test('cannot belong to a profile that does not exist', () async {
      await expectLater(
        addInstance('movies', profileId: 'gone'),
        throwsA(anything),
      );
    });

    test('hold one set of preferences', () async {
      await database
          .into(database.appPreferences)
          .insert(AppPreferencesCompanion.insert());

      await expectLater(
        database
            .into(database.appPreferences)
            .insert(AppPreferencesCompanion.insert(id: const Value(1))),
        throwsA(anything),
      );
    });
  });
}
