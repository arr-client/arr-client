// Browsing the music library (story 8, scenario 1): artists, their albums by
// type, and tracks with file state, with details and artwork.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';
import 'support.dart';

Future<Map<int, Artist>> _list(Harness harness) async => {
  for (final item in await ok(harness.library.list()))
    item.ref.remoteId: item as Artist,
};

Future<Map<int, Album>> _albums(Harness harness, [int artist = 1]) async => {
  for (final item in await ok(harness.library.children(artistRef(artist))))
    item.ref.remoteId: item as Album,
};

Future<Map<int, Track>> _tracks(Harness harness, int album) async => {
  for (final item in await ok(harness.library.children(albumRef(album))))
    item.ref.remoteId: item as Track,
};

/// Whether the allow-list lets the artwork loader ask for [instancePath].
bool _permitted(String instancePath) {
  final uri = Uri.parse(instancePath);
  return allowList.permits(
    ServiceRequest(HttpMethod.get, uri.path, query: uri.queryParametersAll),
  );
}

/// The address of an image of [raw] below the instance, as the server gave it.
String _coverQuery(Map<String, Object?> raw, String type) {
  final image = (raw['images']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((image) => image['coverType'] == type);
  return Uri.parse(image['url']! as String).query;
}

void main() {
  test('the library is of artists', () {
    expect(Harness().library.itemKind, MediaKind.artist);
  });

  group('artists', () {
    test('every artist, keyed to this instance', () async {
      final items = await ok(Harness().library.list());

      expect(items, everyElement(isA<Artist>()));
      expect(
        items.map((item) => item.ref),
        unorderedEquals([artistRef(1), artistRef(2)]),
      );
    });

    test('maps the fields of an artist', () async {
      final harness = Harness();
      final raw = byId(harness.server.artists, 1);

      final found = (await _list(harness))[1]!;

      expect(found.title, raw['artistName']);
      expect(found.sortTitle, raw['sortName']);
      expect(found.monitored, isTrue);
      expect(found.metadataProfileId, raw['metadataProfileId']);
      expect(found.qualityProfileId, raw['qualityProfileId']);
      expect(found.tagIds, {1});
      expect(found.path, raw['path']);
      expect(
        found.sizeOnDisk,
        (raw['statistics']! as Map<String, Object?>)['sizeOnDisk'],
      );
      expect(found.addedAt, DateTime.parse(raw['added']! as String));
      expect(found.parent, isNull);
    });

    test('reads the artists and the queue, nothing else', () async {
      final harness = Harness();

      await ok(harness.library.list());

      expect(harness.server.requests.map((request) => request.path).toSet(), {
        'api/v1/artist',
        'api/v1/queue',
      });
    });

    // Artist 1 wants more tracks than it has; artist 2 wants none.
    test('derives the state from the statistics and the queue', () async {
      final queued = await _list(Harness());
      final idle = await _list(Harness()..server.queue.clear());

      expect(queued[1]!.state, ItemState.downloading);
      expect(idle[1]!.state, ItemState.partial);
      expect(idle[2]!.state, ItemState.unmonitored);
    });

    test('one with every wanted track is downloaded', () async {
      final harness = Harness()..server.queue.clear();
      final raw = byId(harness.server.artists, 1);
      raw['statistics'] = {
        ...raw['statistics']! as Map<String, Object?>,
        'trackCount': 15,
        'trackFileCount': 15,
      };

      expect((await _list(harness))[1]!.state, ItemState.downloaded);
    });

    test('a stored cover is read from the API, keeping its query', () async {
      final harness = Harness();
      final raw = byId(harness.server.artists, 1);

      final found = (await _list(harness))[1]!;

      final poster = found.images.singleWhere(
        (image) => image.type == MediaImageType.poster,
      );
      expect(
        poster.instancePath,
        'api/v1/mediacover/artist/1/poster.jpg?${_coverQuery(raw, 'poster')}',
      );
      for (final image in found.images) {
        if (image.instancePath case final path?) {
          expect(_permitted(path), isTrue, reason: path);
        }
      }
    });
  });

  group('albums', () {
    test('of an artist, with their type, date and artist', () async {
      final harness = Harness()..server.queue.clear();
      final artistName = byId(harness.server.artists, 1)['artistName'];
      final raw = byId(harness.server.albums, 2);

      final albums = await _albums(harness);

      expect(albums.keys, unorderedEquals([1, 2, 3]));
      final found = albums[2]!;
      expect(found.ref, albumRef(2));
      expect(found.title, raw['title']);
      expect(found.albumType, 'Album');
      expect(found.releaseDate?.toUtc(), DateTime.utc(1994, 8, 22));
      expect(found.year, 1994);
      expect(found.monitored, isTrue);
      expect(found.parent, artistRef(1));
      expect(found.parentTitle, artistName);
    });

    test('keep the type the server gives', () async {
      final harness = Harness();
      byId(harness.server.albums, 2)['albumType'] = 'EP';

      expect((await _albums(harness))[2]!.albumType, 'EP');
    });

    test('derive their state from the statistics and the queue', () async {
      final queued = await _albums(Harness());
      final idle = await _albums(Harness()..server.queue.clear());
      final other = await _albums(Harness()..server.queue.clear(), 2);

      // The queue has downloads of albums 1 and 3.
      expect(queued[1]!.state, ItemState.downloading);
      expect(queued[2]!.state, ItemState.downloaded);
      expect(queued[3]!.state, ItemState.downloading);
      expect(idle[1]!.state, ItemState.partial);
      expect(idle[3]!.state, ItemState.missing);
      expect(other[4]!.state, ItemState.unmonitored);
    });

    test('one not released yet is unreleased', () async {
      final harness = Harness()..server.queue.clear();
      // The server does not count the tracks of one as wanted.
      final raw = byId(harness.server.albums, 3);
      raw['releaseDate'] = '2999-01-01T00:00:00Z';
      raw['statistics'] = {
        ...raw['statistics']! as Map<String, Object?>,
        'trackCount': 0,
      };

      expect((await _albums(harness))[3]!.state, ItemState.unreleased);
    });

    test('a cover is read from the API', () async {
      final harness = Harness();
      final raw = byId(harness.server.albums, 2);

      final found = (await _albums(harness))[2]!;

      final cover = found.images.singleWhere(
        (image) => image.type == MediaImageType.cover,
      );
      expect(
        cover.instancePath,
        'api/v1/mediacover/album/2/cover.jpg?${_coverQuery(raw, 'cover')}',
      );
      expect(_permitted(cover.instancePath!), isTrue);
    });

    // An empty list of albums does not say that the artist is gone.
    test('of an artist the server does not have are not found', () async {
      final harness = Harness();

      expect(
        await failureOf(harness.library.children(artistRef(99))),
        isA<NotFound>(),
      );
    });
  });

  group('tracks', () {
    test('of an album, with number, disc, length and file', () async {
      final harness = Harness();
      final raw = byId(harness.server.tracks, 188);

      final tracks = await _tracks(harness, 2);

      expect(
        tracks.keys,
        unorderedEquals([
          for (final track in records('track_album_2')) track['id'],
        ]),
      );
      final found = tracks[188]!;
      expect(found.ref, trackRef(188));
      expect(found.title, raw['title']);
      expect(found.trackNumber, raw['trackNumber']);
      expect(found.discNumber, raw['mediumNumber']);
      expect(found.duration, Duration(milliseconds: raw['duration']! as int));
      expect(found.hasFile, isTrue);
      expect(found.state, ItemState.downloaded);
      expect(found.parent, albumRef(2));
      expect(found.parentTitle, byId(harness.server.albums, 2)['title']);
    });

    // A track has no flag of its own.
    test(
      'without a file take whether they are wanted from the album',
      () async {
        for (final (monitored, state) in [
          (true, ItemState.missing),
          (false, ItemState.unmonitored),
        ]) {
          final harness = Harness()..server.queue.clear();
          byId(harness.server.albums, 2)['monitored'] = monitored;
          byId(harness.server.tracks, 188)['hasFile'] = false;

          final found = (await _tracks(harness, 2))[188]!;

          expect(found.hasFile, isFalse);
          expect(found.monitored, monitored);
          expect(found.state, state);
        }
      },
    );

    test('of an album the server does not have are not found', () async {
      expect(
        await failureOf(Harness().library.children(albumRef(99))),
        isA<NotFound>(),
      );
    });
  });

  group('one item', () {
    test('an artist', () async {
      final harness = Harness();

      final item = await ok(harness.library.item(artistRef(1)));

      expect(item, isA<Artist>());
      expect(item.ref, artistRef(1));
      expect(item.title, byId(harness.server.artists, 1)['artistName']);
    });

    test('an album', () async {
      final harness = Harness();

      final item = await ok(harness.library.item(albumRef(2)));

      expect(item, isA<Album>());
      expect(item.ref, albumRef(2));
      expect(item.parent, artistRef(1));
      expect(item.parentTitle, byId(harness.server.artists, 1)['artistName']);
    });

    for (final ref in [artistRef(99), albumRef(99)]) {
      test('a ${ref.kind.name} that is gone leaves the cache', () async {
        final harness = Harness();
        await ok(harness.library.list());
        await harness.cache.put(
          CacheEntry(
            instanceId: instanceId,
            kind: ref.kind,
            remoteId: 99,
            parentRemoteId: ref.kind == MediaKind.album ? 1 : null,
            sortTitle: 'gone',
            state: ItemState.missing,
            monitored: true,
            tagIds: const [],
            rawJson: '{}',
            fetchedAt: DateTime.now().toUtc(),
          ),
        );

        expect(await failureOf(harness.library.item(ref)), isA<NotFound>());
        expect(await harness.cache.entry(ref.kind, 99), isNull);
      });
    }
  });

  group('cache', () {
    test('has nothing before a fetch', () async {
      final harness = Harness();

      expect(await ok(harness.library.cachedList()), isNull);
      expect(await ok(harness.library.cachedItem(artistRef(1))), isNull);
      expect(await ok(harness.library.cachedChildren(artistRef(1))), isNull);
      expect(await ok(harness.library.cachedChildren(albumRef(2))), isNull);
      expect(harness.server.requests, isEmpty);
    });

    test('keeps artists, albums and tracks for offline use', () async {
      final harness = Harness();
      final artists = await ok(harness.library.list());
      final albums = await ok(harness.library.children(artistRef(1)));
      final tracks = await ok(harness.library.children(albumRef(2)));
      harness.server
        ..requests.clear()
        ..goOffline();

      final cachedArtists = await ok(harness.library.cachedList());
      final cachedAlbums = await ok(
        harness.library.cachedChildren(artistRef(1)),
      );
      final cachedTracks = await ok(
        harness.library.cachedChildren(albumRef(2)),
      );
      final cachedAlbum = await ok(harness.library.cachedItem(albumRef(2)));

      List<(ItemRef, String, ItemState, String?)> summary(
        List<LibraryItem> items,
      ) => [
        for (final item in items)
          (item.ref, item.title, item.state, item.parentTitle),
      ];
      expect(summary(cachedArtists!.value), unorderedEquals(summary(artists)));
      expect(summary(cachedAlbums!.value), unorderedEquals(summary(albums)));
      expect(summary(cachedTracks!.value), unorderedEquals(summary(tracks)));
      expect(cachedAlbum!.value, isA<Album>());
      expect(cachedAlbum.value.parent, artistRef(1));
      expect(harness.server.requests, isEmpty);
    });

    test('is left as it was when the queue cannot be read', () async {
      final harness = Harness();
      harness.server.overrides['queue'] = FakeLidarr.body('', status: 500);

      expect(await failureOf(harness.library.list()), isA<ServerError>());
      expect(await ok(harness.library.cachedList()), isNull);
    });
  });

  group('files', () {
    test('of an album', () async {
      final harness = Harness();
      final raw = byId(harness.server.trackFiles, 1);

      final files = await ok(harness.library.files(albumRef(2)));

      expect(harness.asked, [line(HttpMethod.get, 'trackfile')]);
      expect(harness.server.requests.single.query, {
        'albumId': ['2'],
      });
      expect(
        files.map((file) => file.id),
        unorderedEquals([
          for (final file in records('trackfile_album_2')) file['id'],
        ]),
      );
      final file = files.singleWhere((file) => file.id == 1);
      expect(file.path, raw['path']);
      expect(file.size, raw['size']);
      expect(file.quality?.name, 'MP3-192');
      expect(file.audio, contains('MP3'));
      expect(file.video, isNull);
    });

    test('of an artist', () async {
      final harness = Harness();

      final files = await ok(harness.library.files(artistRef(1)));

      expect(harness.server.requests.single.query, {
        'artistId': ['1'],
      });
      expect(files, hasLength(harness.server.trackFiles.length));
    });

    test('of an album that is gone are not found', () async {
      expect(
        await failureOf(Harness().library.files(albumRef(99))),
        isA<NotFound>(),
      );
    });
  });

  test('there are no credits, and nothing is asked', () async {
    final harness = Harness();

    expect(await ok(harness.library.credits(artistRef(1))), isEmpty);
    expect(harness.server.requests, isEmpty);
  });

  test('a record it cannot understand is malformed', () async {
    final harness = Harness();
    byId(harness.server.artists, 1).remove('id');

    expect(await failureOf(harness.library.list()), isA<MalformedResponse>());
  });
}
