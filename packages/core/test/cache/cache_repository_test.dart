import 'package:core/src/cache/cache_entry.dart';
import 'package:core/src/cache/cache_repository.dart';
import 'package:core/src/cache/cache_scope.dart';
import 'package:core/src/instances/auth_kind.dart';
import 'package:core/src/models/item_state.dart';
import 'package:core/src/models/media_kind.dart';
import 'package:core/src/storage/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _first = DateTime.utc(2026, 1, 2, 3, 4, 5, 6);
final _second = DateTime.utc(2026, 1, 3);
final _third = DateTime.utc(2026, 1, 4);

CacheEntry _entry(
  int remoteId, {
  String instanceId = 'home',
  MediaKind kind = MediaKind.movie,
  int? parentRemoteId,
  String? sortTitle,
  DateTime? fetchedAt,
}) => CacheEntry(
  instanceId: instanceId,
  kind: kind,
  remoteId: remoteId,
  parentRemoteId: parentRemoteId,
  sortTitle: sortTitle ?? 'title $remoteId',
  state: ItemState.missing,
  monitored: true,
  rawJson: '{"id":$remoteId}',
  fetchedAt: fetchedAt ?? _first,
);

CacheEntry _episode(int remoteId, int seriesId) =>
    _entry(remoteId, kind: MediaKind.episode, parentRemoteId: seriesId);

void main() {
  late AppDatabase database;
  late CacheRepository repository;
  late CacheScope cache;
  late DateTime now;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    now = _first;
    repository = CacheRepository(database, now: () => now);
    cache = repository.scope('home');
    await database
        .into(database.profiles)
        .insert(ProfilesCompanion.insert(id: 'default', name: 'Default'));
    for (final id in ['home', 'other']) {
      await database
          .into(database.instances)
          .insert(
            InstancesCompanion.insert(
              id: id,
              profileId: 'default',
              name: id,
              serviceType: 'radarr',
              url: 'http://nas.test/radarr',
              authKind: AuthKind.apiKey,
              createdAt: _first,
              updatedAt: _first,
            ),
          );
    }
  });
  tearDown(() => database.close());

  Future<List<int>?> ids(
    MediaKind kind, {
    int? parent,
    CacheScope? from,
  }) async {
    final snapshot = await (from ?? cache).read(kind, parentRemoteId: parent);
    return snapshot?.entries.map((entry) => entry.remoteId).toList();
  }

  group('entries', () {
    test('keep every field, with times in UTC', () async {
      await cache.put(
        CacheEntry(
          instanceId: 'home',
          kind: MediaKind.album,
          remoteId: 7,
          parentRemoteId: 3,
          sortTitle: 'alpha',
          state: ItemState.partial,
          monitored: false,
          qualityProfileId: 4,
          tagIds: const [3, 5],
          addedAt: _second.toLocal(),
          rawJson: '{"id":7,"unknown":[1]}',
          fetchedAt: _first.toLocal(),
        ),
      );

      final entry = (await cache.entry(MediaKind.album, 7))!;
      expect(entry.instanceId, 'home');
      expect(entry.kind, MediaKind.album);
      expect(entry.remoteId, 7);
      expect(entry.parentRemoteId, 3);
      expect(entry.sortTitle, 'alpha');
      expect(entry.state, ItemState.partial);
      expect(entry.monitored, isFalse);
      expect(entry.qualityProfileId, 4);
      expect(entry.tagIds, [3, 5]);
      expect(entry.addedAt, _second);
      expect(entry.addedAt!.isUtc, isTrue);
      expect(entry.rawJson, '{"id":7,"unknown":[1]}');
      expect(entry.fetchedAt, _first);
      expect(entry.fetchedAt.isUtc, isTrue);
    });

    test('lose values that the server no longer sends', () async {
      await cache.put(
        CacheEntry(
          instanceId: 'home',
          kind: MediaKind.movie,
          remoteId: 1,
          parentRemoteId: 2,
          sortTitle: 'alpha',
          state: ItemState.missing,
          monitored: true,
          qualityProfileId: 4,
          addedAt: _first,
          rawJson: '{}',
          fetchedAt: _first,
        ),
      );

      await cache.put(_entry(1, fetchedAt: _second));

      final entry = (await cache.entry(MediaKind.movie, 1))!;
      expect(entry.parentRemoteId, isNull);
      expect(entry.qualityProfileId, isNull);
      expect(entry.addedAt, isNull);
      expect(entry.fetchedAt, _second);
    });

    test('are found by kind and id', () async {
      await cache.put(_entry(1));

      expect(await cache.entry(MediaKind.movie, 1), isNotNull);
      expect(await cache.entry(MediaKind.movie, 2), isNull);
      expect(await cache.entry(MediaKind.series, 1), isNull);
    });

    test('put on their own do not count as a fetched list', () async {
      await cache.put(_entry(1));

      expect(await cache.read(MediaKind.movie), isNull);
    });

    test('put into a fetched list appear in it, which keeps its age', () async {
      await cache.replace(MediaKind.movie, [_entry(1)]);

      await cache.put(_entry(2, fetchedAt: _second));

      final snapshot = (await cache.read(MediaKind.movie))!;
      expect(snapshot.entries, hasLength(2));
      expect(snapshot.fetchedAt, _first);
    });
  });

  group('lists', () {
    test('never fetched differ from fetched and empty', () async {
      expect(await cache.read(MediaKind.movie), isNull);

      await cache.replace(MediaKind.movie, []);

      final snapshot = (await cache.read(MediaKind.movie))!;
      expect(snapshot.entries, isEmpty);
      expect(snapshot.fetchedAt, _first);
      expect(snapshot.fetchedAt.isUtc, isTrue);
      expect(await cache.read(MediaKind.series), isNull);
    });

    test('are ordered by sort title', () async {
      await cache.replace(MediaKind.movie, [
        _entry(1, sortTitle: 'c'),
        _entry(2, sortTitle: 'a'),
        _entry(3, sortTitle: 'b'),
      ]);

      expect(await ids(MediaKind.movie), [2, 3, 1]);
    });

    test('take the age of the last fetch', () async {
      await cache.replace(MediaKind.movie, [_entry(1)]);
      now = _second.toLocal();

      await cache.replace(MediaKind.movie, [_entry(1)]);

      expect((await cache.read(MediaKind.movie))!.fetchedAt, _second);
    });

    test('drop what a full fetch no longer has', () async {
      await cache.replace(MediaKind.movie, [_entry(1), _entry(2)]);

      await cache.replace(MediaKind.movie, [_entry(2), _entry(3)]);

      expect(await ids(MediaKind.movie), [2, 3]);
      expect(await cache.entry(MediaKind.movie, 1), isNull);
    });

    test('of one parent leave the others alone', () async {
      await cache.replace(MediaKind.episode, [
        _episode(1, 10),
        _episode(2, 10),
      ], parentRemoteId: 10);
      await cache.replace(MediaKind.episode, [
        _episode(3, 20),
      ], parentRemoteId: 20);
      now = _second;

      await cache.replace(MediaKind.episode, [
        _episode(2, 10),
      ], parentRemoteId: 10);

      expect(await ids(MediaKind.episode, parent: 10), [2]);
      expect(await ids(MediaKind.episode, parent: 20), [3]);
      expect(
        (await cache.read(MediaKind.episode, parentRemoteId: 20))!.fetchedAt,
        _first,
      );
      // One parent is not everything.
      expect(await cache.read(MediaKind.episode), isNull);
      expect(await cache.read(MediaKind.episode, parentRemoteId: 30), isNull);
    });

    test('of a parent are covered by a fetch of everything', () async {
      await cache.replace(MediaKind.book, [
        _entry(1, kind: MediaKind.book, parentRemoteId: 10),
      ], parentRemoteId: 10);
      // An author without books.
      await cache.put(_entry(30, kind: MediaKind.author));
      now = _second;
      await cache.replace(MediaKind.book, [
        _entry(1, kind: MediaKind.book, parentRemoteId: 10),
        _entry(2, kind: MediaKind.book, parentRemoteId: 20),
      ]);

      for (final parent in [10, 20, 30]) {
        final snapshot = await cache.read(
          MediaKind.book,
          parentRemoteId: parent,
        );
        expect(snapshot!.fetchedAt, _second);
      }
      expect(await ids(MediaKind.book, parent: 20), [2]);
      expect(await cache.read(MediaKind.book, parentRemoteId: 40), isNull);

      now = _third;
      await cache.replace(MediaKind.book, [], parentRemoteId: 10);

      expect(
        (await cache.read(MediaKind.book, parentRemoteId: 10))!.fetchedAt,
        _third,
      );
      expect((await cache.read(MediaKind.book))!.fetchedAt, _second);
      expect(await ids(MediaKind.book), [2]);
    });

    test('of a parent added after a full fetch were never fetched', () async {
      await cache.replace(MediaKind.artist, [
        _entry(1, kind: MediaKind.artist),
      ]);
      await cache.replace(MediaKind.album, [
        _entry(10, kind: MediaKind.album, parentRemoteId: 1),
      ]);

      await cache.remove(MediaKind.artist, 1);
      await cache.put(_entry(2, kind: MediaKind.artist));

      for (final artist in [1, 2]) {
        expect(
          await cache.read(MediaKind.album, parentRemoteId: artist),
          isNull,
        );
      }
      expect(await ids(MediaKind.album), isEmpty);
    });

    test('can be larger than one statement allows', () async {
      final series = [
        for (var id = 1; id <= 40000; id++) _entry(id, kind: MediaKind.series),
      ];
      await cache.replace(MediaKind.series, series);
      await cache.put(_episode(1, 40000));

      await cache.replace(MediaKind.series, [series.first]);

      expect(await ids(MediaKind.series), [1]);
      expect(await cache.entry(MediaKind.episode, 1), isNull);
    });
  });

  group('removal', () {
    test('takes an item out of its list', () async {
      await cache.replace(MediaKind.movie, [_entry(1), _entry(2)]);

      await cache.remove(MediaKind.movie, 1);

      expect(await ids(MediaKind.movie), [2]);
      expect(await cache.entry(MediaKind.movie, 1), isNull);
    });

    Future<void> addArtists() async {
      await cache.replace(MediaKind.artist, [
        _entry(1, kind: MediaKind.artist),
        _entry(2, kind: MediaKind.artist),
      ]);
      for (final artist in [1, 2]) {
        final album = _entry(
          artist * 10,
          kind: MediaKind.album,
          parentRemoteId: artist,
        );
        await cache.replace(MediaKind.album, [album], parentRemoteId: artist);
        await cache.replace(MediaKind.track, [
          _entry(
            artist * 100,
            kind: MediaKind.track,
            parentRemoteId: album.remoteId,
          ),
        ], parentRemoteId: album.remoteId);
      }
    }

    Future<void> expectOnlyArtist2() async {
      expect(await ids(MediaKind.artist), [2]);
      expect(await cache.entry(MediaKind.album, 10), isNull);
      expect(await cache.entry(MediaKind.track, 100), isNull);
      expect(await cache.read(MediaKind.album, parentRemoteId: 1), isNull);
      expect(await cache.read(MediaKind.track, parentRemoteId: 10), isNull);
      expect(await ids(MediaKind.album, parent: 2), [20]);
      expect(await ids(MediaKind.track, parent: 20), [200]);
    }

    test('takes everything under the item', () async {
      await addArtists();

      await cache.remove(MediaKind.artist, 1);

      await expectOnlyArtist2();
    });

    test('by a full fetch takes everything under the item', () async {
      await addArtists();

      await cache.replace(MediaKind.artist, [
        _entry(2, kind: MediaKind.artist),
      ]);

      await expectOnlyArtist2();
    });

    test('of a series leaves an author with its id', () async {
      await cache.put(_episode(1, 5));
      await cache.put(_entry(1, kind: MediaKind.book, parentRemoteId: 5));

      await cache.remove(MediaKind.series, 5);

      expect(await cache.entry(MediaKind.episode, 1), isNull);
      expect(await cache.entry(MediaKind.book, 1), isNotNull);
    });
  });

  group('instances', () {
    test('do not see or change each other', () async {
      final other = repository.scope('other');
      await other.replace(MediaKind.series, [
        _entry(1, instanceId: 'other', kind: MediaKind.series),
      ]);
      await other.put(
        _entry(
          2,
          instanceId: 'other',
          kind: MediaKind.episode,
          parentRemoteId: 1,
        ),
      );

      expect(await cache.read(MediaKind.series), isNull);
      expect(await cache.entry(MediaKind.series, 1), isNull);
      await cache.replace(MediaKind.series, []);
      await cache.remove(MediaKind.series, 1);

      expect(await ids(MediaKind.series, from: other), [1]);
      expect(await other.entry(MediaKind.episode, 2), isNotNull);
    });

    test('cannot be written to through another one', () async {
      final foreign = _entry(1, instanceId: 'other');

      await expectLater(cache.put(foreign), throwsArgumentError);
      await expectLater(
        cache.replace(MediaKind.movie, [_entry(2), foreign]),
        throwsArgumentError,
      );

      expect(await database.select(database.cacheEntries).get(), isEmpty);
      expect(await cache.read(MediaKind.movie), isNull);
    });

    test('take only entries of the kind and parent fetched', () async {
      await expectLater(
        cache.replace(MediaKind.series, [_entry(1)]),
        throwsArgumentError,
      );
      await expectLater(
        cache.replace(MediaKind.episode, [_episode(1, 20)], parentRemoteId: 10),
        throwsArgumentError,
      );

      expect(await database.select(database.cacheEntries).get(), isEmpty);
      expect(await database.select(database.cacheFetches).get(), isEmpty);
    });

    test('lose their cache when deleted', () async {
      await cache.replace(MediaKind.movie, [_entry(1)]);

      await (database.delete(
        database.instances,
      )..where((row) => row.id.equals('home'))).go();

      expect(await cache.read(MediaKind.movie), isNull);
      expect(await cache.entry(MediaKind.movie, 1), isNull);
    });
  });

  test('clearing removes the cache of every instance', () async {
    final other = repository.scope('other');
    await cache.replace(MediaKind.movie, [_entry(1)]);
    await other.replace(MediaKind.movie, [_entry(1, instanceId: 'other')]);

    await repository.clear();

    for (final scope in [cache, other]) {
      expect(await scope.read(MediaKind.movie), isNull);
      expect(await scope.entry(MediaKind.movie, 1), isNull);
    }
    expect(await database.select(database.instances).get(), hasLength(2));
  });
}
