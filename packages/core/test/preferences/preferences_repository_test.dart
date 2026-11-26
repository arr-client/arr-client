import 'dart:io';

import 'package:core/core.dart';
// The tests also write rows that only another version of the app would.
import 'package:core/src/storage/database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026, 1, 2);

final _view = LibraryView(
  layout: LibraryLayout.list,
  sort: const LibrarySort(field: 'added', ascending: false),
  filters: LibraryFilters(
    text: 'alien',
    states: const {ItemState.missing, ItemState.downloading},
    monitored: false,
    qualityProfiles: {const InstanceOptionId('movies', 4)},
    tags: {
      const InstanceOptionId('movies', 1),
      const InstanceOptionId('more', 1),
    },
  ),
  instanceScope: 'movies',
);

void main() {
  late AppDatabase database;
  late PreferencesRepository repository;

  void openInMemory() {
    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = PreferencesRepository(database);
    });
    tearDown(() => database.close());
  }

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

  Future<void> deleteInstance(String id) => (database.delete(
    database.instances,
  )..where((row) => row.id.equals(id))).go();

  Future<void> addHome() async {
    await addProfile('home');
    await addInstance('movies');
    await addInstance('more');
  }

  test('preferences survive closing the database', () async {
    final directory = await Directory.systemTemp.createTemp('preferences');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/app.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await PreferencesRepository(first).setThemeMode(AppThemeMode.light);
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);

    expect(
      (await PreferencesRepository(second).read()).themeMode,
      AppThemeMode.light,
    );
  });

  group('app-wide preferences', () {
    openInMemory();

    test('have defaults before anything is stored', () async {
      final preferences = await repository.read();

      expect(preferences.activeProfileId, isNull);
      expect(preferences.themeMode, AppThemeMode.system);
      expect(preferences.trueBlack, isFalse);
      expect(preferences.dynamicColor, isTrue);
      expect(preferences.loadThirdPartyArtwork, isTrue);
      expect(preferences.appLock, const AppLock());
    });

    test('have the same defaults as the database', () async {
      await database
          .into(database.appPreferences)
          .insert(AppPreferencesCompanion.insert());

      expect(await repository.read(), const Preferences());
    });

    test('are changed one at a time without losing the others', () async {
      await addProfile('home');

      await repository.setThemeMode(AppThemeMode.dark);
      await repository.setActiveProfile('home');
      await repository.setTrueBlack(true);
      await repository.setDynamicColor(false);
      await repository.setLoadThirdPartyArtwork(false);
      await repository.setAppLock(
        const AppLock(enabled: true, delaySeconds: 60),
      );

      expect(
        await repository.read(),
        const Preferences(
          activeProfileId: 'home',
          themeMode: AppThemeMode.dark,
          trueBlack: true,
          dynamicColor: false,
          loadThirdPartyArtwork: false,
          appLock: AppLock(enabled: true, delaySeconds: 60),
        ),
      );
    });

    test('are watched', () async {
      final changes = expectLater(
        repository.watch(),
        emitsInOrder([const Preferences(), const Preferences(trueBlack: true)]),
      );
      await pumpEventQueue();

      await repository.setTrueBlack(true);

      await changes;
    });

    test('forget a deleted active profile', () async {
      await addProfile('home');
      await repository.setActiveProfile('home');

      await database.delete(database.profiles).go();

      expect((await repository.read()).activeProfileId, isNull);
    });

    test('refuse a profile that does not exist', () async {
      await expectLater(repository.setActiveProfile('gone'), throwsA(anything));
    });

    test('refuse a negative lock delay', () {
      expect(
        () => repository.setAppLock(const AppLock(delaySeconds: -1)),
        throwsRangeError,
      );
    });

    test('read an unknown theme as the system theme', () async {
      await database
          .into(database.appPreferences)
          .insert(
            AppPreferencesCompanion.insert(themeMode: const Value('sepia')),
          );

      expect((await repository.read()).themeMode, AppThemeMode.system);
    });
  });

  group('views', () {
    openInMemory();

    test('are the default until saved', () async {
      await addHome();

      expect(
        await repository.view('home', MediaKind.movie),
        const LibraryView(),
      );
    });

    test('keep every field', () async {
      await addHome();

      await repository.saveView('home', MediaKind.movie, _view);

      expect(await repository.view('home', MediaKind.movie), _view);
    });

    test('are kept by profile and library', () async {
      await addHome();
      await addProfile('away');

      await repository.saveView('home', MediaKind.movie, _view);

      expect(
        await repository.view('home', MediaKind.series),
        const LibraryView(),
      );
      expect(
        await repository.view('away', MediaKind.movie),
        const LibraryView(),
      );
    });

    test('replace what was saved, including with no scope', () async {
      await addHome();
      await repository.saveView('home', MediaKind.movie, _view);

      await repository.saveView('home', MediaKind.movie, const LibraryView());

      expect(
        await repository.view('home', MediaKind.movie),
        const LibraryView(),
      );
    });

    test('drop a deleted instance when read', () async {
      await addHome();
      await repository.saveView('home', MediaKind.movie, _view);

      await deleteInstance('movies');

      final view = await repository.view('home', MediaKind.movie);
      expect(view.instanceScope, isNull);
      expect(view.filters.qualityProfiles, isEmpty);
      expect(view.filters.tags, {const InstanceOptionId('more', 1)});
      expect(view.filters.text, 'alien');
      expect(view.layout, LibraryLayout.list);
    });

    test('drop an instance of another profile when read', () async {
      await addProfile('home');
      await addProfile('away');
      await addInstance('movies', profileId: 'away');

      await repository.saveView(
        'home',
        MediaKind.movie,
        const LibraryView(instanceScope: 'movies'),
      );

      expect(
        (await repository.view('home', MediaKind.movie)).instanceScope,
        isNull,
      );
    });

    test('lose the stored data of a removed instance', () async {
      await addHome();
      await repository.saveView('home', MediaKind.movie, _view);

      await repository.removeInstanceFromViews('movies');

      final row = await database.select(database.viewPreferences).getSingle();
      expect(row.instanceScope, isNull);
      expect(row.filters, isNot(contains('movies')));
      expect(row.filters, contains('more'));
    });

    test('are copied with the instance ids of the copy', () async {
      await addHome();
      await addProfile('copy');
      await addInstance('movies-copy', profileId: 'copy');
      await addInstance('more-copy', profileId: 'copy');
      await repository.saveView('home', MediaKind.movie, _view);
      await repository.saveView(
        'home',
        MediaKind.series,
        const LibraryView(layout: LibraryLayout.list),
      );

      await repository.copyViews(
        fromProfileId: 'home',
        toProfileId: 'copy',
        instanceIds: {'movies': 'movies-copy', 'more': 'more-copy'},
      );

      final copy = await repository.view('copy', MediaKind.movie);
      expect(copy.instanceScope, 'movies-copy');
      expect(copy.filters.qualityProfiles, {
        const InstanceOptionId('movies-copy', 4),
      });
      expect(copy.filters.tags, {
        const InstanceOptionId('movies-copy', 1),
        const InstanceOptionId('more-copy', 1),
      });
      expect(copy.sort, _view.sort);
      expect(
        (await repository.view('copy', MediaKind.series)).layout,
        LibraryLayout.list,
      );
      expect(await repository.view('home', MediaKind.movie), _view);
    });

    test('read unknown and missing values as the defaults', () async {
      await addProfile('home');
      await database
          .into(database.viewPreferences)
          .insert(
            ViewPreferencesCompanion.insert(
              profileId: 'home',
              library: 'movie',
              layout: 'carousel',
              sort: '{}',
              filters: '{"states":["missing","lost"],"tags":[7],"new":1}',
            ),
          );

      expect(
        await repository.view('home', MediaKind.movie),
        const LibraryView(filters: LibraryFilters(states: {ItemState.missing})),
      );
    });

    test('drop options a server no longer has, keeping unknown servers', () {
      final filters = _view.filters.withoutUnresolved({
        'movies': const [
          // A quality profile with the id of the tag does not resolve it.
          ServerOption(
            kind: ServerOptionKind.qualityProfile,
            id: 1,
            label: 'HD',
          ),
          ServerOption(
            kind: ServerOptionKind.qualityProfile,
            id: 4,
            label: 'UHD',
          ),
        ],
      });

      expect(filters.qualityProfiles, _view.filters.qualityProfiles);
      expect(filters.tags, {const InstanceOptionId('more', 1)});
      expect(filters.states, _view.filters.states);
    });
  });

  group('last add choices', () {
    openInMemory();

    const choices = AddChoices(
      rootFolderId: 1,
      qualityProfileId: 2,
      monitorOptionId: 'all',
      searchNow: true,
      metadataProfileId: 3,
      tagIds: {4, 5},
      seriesType: SeriesType.anime,
      seasonFolder: false,
      minimumAvailability: MinimumAvailability.inCinemas,
    );

    test('are null until saved', () async {
      await addHome();

      expect(await repository.lastAddChoices('movies'), isNull);
    });

    test('keep every field, per instance', () async {
      await addHome();

      await repository.saveLastAddChoices('movies', choices);

      final read = (await repository.lastAddChoices('movies'))!;
      expect(read.rootFolderId, 1);
      expect(read.qualityProfileId, 2);
      expect(read.monitorOptionId, 'all');
      expect(read.searchNow, isTrue);
      expect(read.metadataProfileId, 3);
      expect(read.tagIds, {4, 5});
      expect(read.seriesType, SeriesType.anime);
      expect(read.seasonFolder, isFalse);
      expect(read.minimumAvailability, MinimumAvailability.inCinemas);
      expect(await repository.lastAddChoices('more'), isNull);
    });

    test('replace what was saved', () async {
      await addHome();
      await repository.saveLastAddChoices('movies', choices);

      await repository.saveLastAddChoices(
        'movies',
        const AddChoices(
          rootFolderId: 9,
          qualityProfileId: 2,
          monitorOptionId: 'none',
          searchNow: false,
        ),
      );

      final read = (await repository.lastAddChoices('movies'))!;
      expect(read.rootFolderId, 9);
      expect(read.metadataProfileId, isNull);
      expect(read.tagIds, isEmpty);
      expect(read.seriesType, isNull);
    });

    test('are deleted with their instance', () async {
      await addHome();
      await repository.saveLastAddChoices('movies', choices);

      await deleteInstance('movies');

      expect(await database.select(database.lastAddChoices).get(), isEmpty);
    });

    test('are null when a required choice is missing', () async {
      await addHome();
      await database
          .into(database.lastAddChoices)
          .insert(
            LastAddChoicesCompanion.insert(
              instanceId: 'movies',
              choices: '{"rootFolderId":1}',
            ),
          );

      expect(await repository.lastAddChoices('movies'), isNull);
    });
  });
}
