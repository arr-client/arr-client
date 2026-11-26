// Searching for artists and albums, finding one again and the choices for
// adding it (story 8, scenario 3).
//
// The searches were recorded before and after artist 1 was added: `artist_lookup`
// and `album_lookup` before, so they name no library item.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Map<String, Object?> _raw(String fixture, [int index = 0]) =>
    records(fixture)[index];

AddCandidate _candidate(MediaKind kind, String? musicBrainzId) => AddCandidate(
  kind: kind,
  title: 'Found elsewhere',
  externalIds: ExternalIds(musicBrainzId: musicBrainzId),
);

void main() {
  test('adds artists and albums', () {
    expect(Harness().lookup.itemKinds, {MediaKind.artist, MediaKind.album});
  });

  group('lookup', () {
    test('searches for artists and for albums', () async {
      final harness = Harness();

      final found = await ok(harness.lookup.lookup(FakeLidarr.searchTerm));

      expect(harness.server.requests.map((request) => request.path).toSet(), {
        'api/v1/artist/lookup',
        'api/v1/album/lookup',
      });
      for (final request in harness.server.requests) {
        expect(request.query, {
          'term': [FakeLidarr.searchTerm],
        });
      }
      expect(
        found.where((candidate) => candidate.kind == MediaKind.artist),
        hasLength(records('artist_lookup').length),
      );
      expect(
        found.where((candidate) => candidate.kind == MediaKind.album),
        hasLength(records('album_lookup').length),
      );
    });

    test('maps an artist', () async {
      final raw = _raw('artist_lookup');

      final found = (await ok(Harness().lookup.lookup(FakeLidarr.searchTerm)))
          .firstWhere((candidate) => candidate.kind == MediaKind.artist);

      expect(found.title, raw['artistName']);
      expect(found.parentTitle, isNull);
      expect(found.externalIds.musicBrainzId, raw['foreignArtistId']);
      expect(found.existingRefs, isEmpty);
      expect(found.sourceByInstance, {instanceId: raw});
    });

    test('maps an album and names its artist', () async {
      final raw = _raw('album_lookup', 1);
      final artist = raw['artist']! as Map<String, Object?>;

      final found = (await ok(Harness().lookup.lookup(FakeLidarr.searchTerm)))
          .where((candidate) => candidate.kind == MediaKind.album)
          .toList()[1];

      expect(found.title, raw['title']);
      expect(found.parentTitle, artist['artistName']);
      expect(found.externalIds.musicBrainzId, raw['foreignAlbumId']);
      expect(found.year, DateTime.parse(raw['releaseDate']! as String).year);
      expect(found.existingRefs, isEmpty);
      expect(found.sourceByInstance, {instanceId: raw});
    });

    // The proxied address is behind the web UI's sign-in.
    test('shows the public cover of what the library does not have', () async {
      final found = await ok(Harness().lookup.lookup(FakeLidarr.searchTerm));

      for (final candidate in found) {
        for (final image in candidate.images) {
          expect(image.instancePath, isNull);
          expect(image.remoteUrl, isNotNull);
        }
      }
      expect(
        found
            .firstWhere((candidate) => candidate.kind == MediaKind.album)
            .images,
        isNotEmpty,
      );
    });

    test('names the library item of what the server has', () async {
      final harness = Harness();
      harness.server.artistLookup
        ..clear()
        ..addAll(records('artist_lookup_existing'));
      harness.server.albumLookup.first['id'] = 2;

      final found = await ok(harness.lookup.lookup(FakeLidarr.searchTerm));

      expect(
        found
            .firstWhere((candidate) => candidate.kind == MediaKind.artist)
            .existingRefs,
        [artistRef(1)],
      );
      expect(
        found
            .firstWhere((candidate) => candidate.kind == MediaKind.album)
            .existingRefs,
        [albumRef(2)],
      );
    });

    for (final term in ['', '   ']) {
      test('sends nothing for "$term"', () async {
        final harness = Harness();

        expect(await ok(harness.lookup.lookup(term)), isEmpty);
        expect(harness.server.requests, isEmpty);
      });
    }

    for (final path in ['artist/lookup', 'album/lookup']) {
      test('fails when $path does', () async {
        final harness = Harness();
        harness.server.overrides[path] = FakeLidarr.body('', status: 503);

        expect(
          await failureOf(harness.lookup.lookup(FakeLidarr.searchTerm)),
          isA<ServerError>(),
        );
      });
    }
  });

  group('find', () {
    test('an artist by its MusicBrainz id', () async {
      final harness = Harness();
      final raw = _raw('artist_lookup_new');
      final id = raw['foreignArtistId']! as String;

      final found = await ok(
        harness.lookup.find(_candidate(MediaKind.artist, id)),
      );

      expect(harness.asked, [line(HttpMethod.get, 'artist/lookup')]);
      expect(harness.server.requests.single.query, {
        'term': ['lidarr:$id'],
      });
      expect(found.title, raw['artistName']);
      expect(found.sourceByInstance, {instanceId: raw});
    });

    test('an album by its MusicBrainz id', () async {
      final harness = Harness();
      final raw = _raw('album_lookup_new');
      final id = raw['foreignAlbumId']! as String;

      final found = await ok(
        harness.lookup.find(_candidate(MediaKind.album, id)),
      );

      expect(harness.asked, [line(HttpMethod.get, 'album/lookup')]);
      expect(harness.server.requests.single.query, {
        'term': ['lidarr:$id'],
      });
      expect(found.title, raw['title']);
      expect(found.sourceByInstance, {instanceId: raw});
    });

    test('says that the instance has it', () async {
      final raw = _raw('artist_lookup_existing');

      final found = await ok(
        Harness().lookup.find(
          _candidate(MediaKind.artist, raw['foreignArtistId']! as String),
        ),
      );

      expect(found.existingRefs, [artistRef(1)]);
    });

    test('one the search does not give is not found', () async {
      expect(
        await failureOf(
          Harness().lookup.find(_candidate(MediaKind.artist, 'unknown')),
        ),
        isA<NotFound>(),
      );
    });

    test('one without an id is not found, and nothing is asked', () async {
      final harness = Harness();

      expect(
        await failureOf(harness.lookup.find(_candidate(MediaKind.album, null))),
        isA<NotFound>(),
      );
      expect(harness.server.requests, isEmpty);
    });
  });

  group('add options', () {
    for (final kind in [MediaKind.artist, MediaKind.album]) {
      test('of an ${kind.name} have both profiles and the choices', () async {
        final options = await ok(Harness().lookup.addOptions(kind));

        expect(
          options.serverOptions.map((option) => option.kind).toSet(),
          ServerOptionKind.values.toSet(),
        );
        expect(options.monitorOptions.map((option) => option.id), [
          'all',
          'future',
          'missing',
          'existing',
          'first',
          'latest',
          'none',
        ]);
      });
    }

    test('are not of anything else', () async {
      final harness = Harness();

      await expectProgrammingError(
        () => harness.lookup.addOptions(MediaKind.movie),
      );

      expect(harness.server.requests, isEmpty);
    });
  });
}
