// Adding an artist or an album with quality and metadata profile, root folder
// and monitoring choice (story 8, scenario 3).
//
// What Lidarr's own web UI posts: the record of the lookup with the choices set
// in it. An album brings its artist along: one the server does not have is made
// with the choices, one it has is left as it is. The refusals were recorded.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

AddChoices _choices({
  int rootFolderId = 1,
  String monitor = 'all',
  bool searchNow = false,
  Set<int> tags = const {1},
}) => AddChoices(
  rootFolderId: rootFolderId,
  qualityProfileId: 4,
  metadataProfileId: 2,
  monitorOptionId: monitor,
  searchNow: searchNow,
  tagIds: tags,
);

/// The candidate this instance's lookup makes of [source].
AddCandidate _candidate(MediaKind kind, Map<String, Object?> source) =>
    AddCandidate(
      kind: kind,
      title: 'New',
      externalIds: ExternalIds(
        musicBrainzId:
            source[kind == MediaKind.artist
                    ? 'foreignArtistId'
                    : 'foreignAlbumId']
                as String?,
      ),
      sourceByInstance: {instanceId: source},
    );

Map<String, Object?> _newArtist() => records('artist_lookup_new').single;

/// An album of an artist the server does not have.
Map<String, Object?> _newAlbum() => records('album_lookup_new').single;

/// A server that has neither the artist nor the album of [_newAlbum].
Harness _withoutIt() {
  final album = _newAlbum();
  return Harness()
    ..server.albums.removeWhere(
      (held) => held['foreignAlbumId'] == album['foreignAlbumId'],
    );
}

Map<String, Object?> _posted(Harness harness) =>
    sentBody(harness.server.writes.single)! as Map<String, Object?>;

void main() {
  group('an artist', () {
    test('is posted as found, with the choices', () async {
      final harness = Harness();
      final source = _newArtist();

      final added = await ok(
        harness.lookup.add(
          _candidate(MediaKind.artist, source),
          _choices(monitor: 'future', searchNow: true),
        ),
      );

      expect(added, artistRef(FakeLidarr.addedId));
      final write = harness.server.writes.single;
      expect(write.method, HttpMethod.post);
      expect(write.path, 'api/v1/artist');
      expect(write.query, isEmpty);
      final body = _posted(harness);
      expect(body['foreignArtistId'], source['foreignArtistId']);
      expect(body['artistName'], source['artistName']);
      expect(body['images'], source['images']);
      expect(body['rootFolderPath'], records('rootfolder').single['path']);
      expect(body['qualityProfileId'], 4);
      expect(body['metadataProfileId'], 2);
      expect(body['tags'], [1]);
      expect(body['monitored'], isTrue);
      expect(body['addOptions'], {
        'monitor': 'future',
        'searchForMissingAlbums': true,
      });
    });

    test('does not change the candidate', () async {
      final source = _newArtist();
      final before = jsonEncode(source);

      await ok(
        Harness().lookup.add(_candidate(MediaKind.artist, source), _choices()),
      );

      expect(jsonEncode(source), before);
    });

    test('from another instance is first looked up here', () async {
      final harness = Harness();
      final source = _newArtist();
      final id = source['foreignArtistId']! as String;

      await ok(
        harness.lookup.add(
          AddCandidate(
            kind: MediaKind.artist,
            title: 'New',
            externalIds: ExternalIds(musicBrainzId: id),
            sourceByInstance: const {
              'i2': {'foreignArtistId': 'theirs', 'id': 9},
            },
          ),
          _choices(),
        ),
      );

      expect(harness.asked, contains(line(HttpMethod.get, 'artist/lookup')));
      expect(_posted(harness)['foreignArtistId'], id);
    });

    test('that the server has is a conflict, with nothing sent', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(
              MediaKind.artist,
              records('artist_lookup_existing').single,
            ),
            _choices(),
          ),
        ),
        isA<Conflict>(),
      );
      expect(harness.server.writes, isEmpty);
    });

    // Added since it was searched for.
    test('refused as already added is a conflict', () async {
      final harness = Harness();
      final source = _newArtist();
      harness.server.artists.add({...source, 'id': 7});

      expect(
        await failureOf(
          harness.lookup.add(_candidate(MediaKind.artist, source), _choices()),
        ),
        isA<Conflict>(),
      );
      expect(harness.server.writes, hasLength(1));
    });

    for (final fixture in ['artist_add_bad_root', 'artist_add_bad_profile']) {
      test('keeps the server\'s refusal, as $fixture', () async {
        final harness = Harness()
          ..server.writeAnswer = FakeLidarr.body(
            jsonEncode(records(fixture)),
            status: 400,
            write: true,
          );

        expect(
          await failureOf(
            harness.lookup.add(
              _candidate(MediaKind.artist, _newArtist()),
              _choices(),
            ),
          ),
          isA<Validation>().having((failure) => failure.messages, 'messages', [
            for (final refusal in records(fixture)) refusal['errorMessage'],
          ]),
        );
      });
    }

    test('without its root folder is refused, with nothing sent', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.artist, _newArtist()),
            _choices(rootFolderId: 99),
          ),
        ),
        isA<Validation>(),
      );
      expect(harness.server.writes, isEmpty);
    });
  });

  group('an album', () {
    test('of a new artist makes the artist with the choices', () async {
      final harness = _withoutIt();
      final source = _newAlbum();
      final artist = source['artist']! as Map<String, Object?>;

      final added = await ok(
        harness.lookup.add(
          _candidate(MediaKind.album, source),
          _choices(monitor: 'none', searchNow: true),
        ),
      );

      expect(added, albumRef(FakeLidarr.addedId));
      final write = harness.server.writes.single;
      expect(write.method, HttpMethod.post);
      expect(write.path, 'api/v1/album');
      final body = _posted(harness);
      expect(body['foreignAlbumId'], source['foreignAlbumId']);
      expect(body['releases'], source['releases']);
      expect(body['monitored'], isTrue);
      expect(body['addOptions'], {'searchForNewAlbum': true});
      final sent = body['artist']! as Map<String, Object?>;
      expect(sent['foreignArtistId'], artist['foreignArtistId']);
      expect(sent['rootFolderPath'], records('rootfolder').single['path']);
      expect(sent['qualityProfileId'], 4);
      expect(sent['metadataProfileId'], 2);
      expect(sent['tags'], [1]);
      expect(sent['monitored'], isTrue);
      // The server would otherwise search for the whole artist.
      expect(sent['addOptions'], {
        'monitor': 'none',
        'searchForMissingAlbums': false,
      });
    });

    test('of an artist the server has leaves the artist as it is', () async {
      final harness = _withoutIt();
      final source = _newAlbum();
      final artist = {
        ...source['artist']! as Map<String, Object?>,
        'id': 2,
        'qualityProfileId': 1,
        'metadataProfileId': 1,
        'path': '/redacted/held',
      };
      source['artist'] = artist;

      await ok(
        harness.lookup.add(_candidate(MediaKind.album, source), _choices()),
      );

      expect(_posted(harness)['artist'], artist);
    });

    test('that the server has is a conflict, with nothing sent', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.album, {..._newAlbum(), 'id': 4}),
            _choices(),
          ),
        ),
        isA<Conflict>(),
      );
      expect(harness.server.writes, isEmpty);
    });

    test('refused as already added is a conflict', () async {
      final harness = Harness();

      // Album 4 is the recorded one.
      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.album, _newAlbum()),
            _choices(),
          ),
        ),
        isA<Conflict>(),
      );
      expect(harness.server.writes, hasLength(1));
    });
  });

  group('failures', () {
    for (final MapEntry(key: cause, value: (answer, expected))
        in writeFailures.entries) {
      test('$cause is reported and the add is sent once', () async {
        final harness = Harness()..server.writeAnswer = answer;

        final failure = await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.artist, _newArtist()),
            _choices(),
          ),
        );

        expect(failure.runtimeType, expected);
        expect(harness.server.writes, hasLength(1));
      });
    }

    test('an accepted add that names nothing has an unknown outcome', () async {
      final harness = Harness()
        ..server.writeAnswer = FakeLidarr.body('{', status: 201);

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.artist, _newArtist()),
            _choices(),
          ),
        ),
        isA<OutcomeUnknown>(),
      );
    });

    test('nothing else can be added', () async {
      final harness = Harness();

      await expectProgrammingError(
        () => harness.lookup.add(
          _candidate(MediaKind.movie, _newArtist()),
          _choices(),
        ),
      );

      expect(harness.server.requests, isEmpty);
    });
  });
}
