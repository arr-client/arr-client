// Editing artists and albums without losing what the app does not know of
// (research R13), and editing several artists at once.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('an artist', () {
    test('changes only the fields set', () async {
      final harness = Harness();
      byId(harness.server.artists, 1)['unknownToTheApp'] = {'kept': true};
      final before = {...byId(harness.server.artists, 1)};

      await ok(
        harness.library.edit(
          artistRef(1),
          const ItemEdit(
            monitored: false,
            qualityProfileId: 1,
            metadataProfileId: 2,
            tagIds: {},
          ),
        ),
      );

      expect(harness.asked, [
        line(HttpMethod.get, 'artist/1'),
        line(HttpMethod.put, 'artist/1'),
      ]);
      expect(sentBody(harness.server.writes.single), {
        ...before,
        'monitored': false,
        'qualityProfileId': 1,
        'metadataProfileId': 2,
        'tags': <int>[],
      });
    });

    test('leaves out what an artist does not have', () async {
      final harness = Harness();
      final before = {...byId(harness.server.artists, 1)};

      await ok(
        harness.library.edit(
          artistRef(1),
          const ItemEdit(
            monitored: false,
            seriesType: SeriesType.anime,
            seasonFolder: true,
            minimumAvailability: MinimumAvailability.released,
          ),
        ),
      );

      expect(sentBody(harness.server.writes.single), {
        ...before,
        'monitored': false,
      });
    });
  });

  group('an album', () {
    test('keeps its releases and the rest of its record', () async {
      final harness = Harness();
      final before = {...byId(harness.server.albums, 2)};

      await ok(
        harness.library.edit(albumRef(2), const ItemEdit(monitored: false)),
      );

      expect(harness.asked, [
        line(HttpMethod.get, 'album/2'),
        line(HttpMethod.put, 'album/2'),
      ]);
      expect(sentBody(harness.server.writes.single), {
        ...before,
        'monitored': false,
      });
    });

    // Its profiles and tags are the artist's.
    test('has nothing to write for the fields of an artist', () async {
      final harness = Harness();

      await ok(
        harness.library.edit(
          albumRef(2),
          const ItemEdit(
            qualityProfileId: 1,
            metadataProfileId: 2,
            tagIds: {1},
          ),
        ),
      );

      expect(harness.server.writes, isEmpty);
    });
  });

  test('with nothing set sends nothing', () async {
    final harness = Harness();

    await ok(harness.library.edit(artistRef(1), const ItemEdit()));

    expect(harness.server.requests, isEmpty);
  });

  group('several artists', () {
    test('are changed by the editor', () async {
      final harness = Harness();

      await ok(
        harness.library.bulkEdit(
          [artistRef(1), artistRef(2)],
          const BulkEdit(
            monitored: true,
            qualityProfileId: 4,
            tagIds: {1},
            tagChange: TagChange.remove,
          ),
        ),
      );

      expect(harness.asked, [line(HttpMethod.put, 'artist/editor')]);
      expect(sentBody(harness.server.writes.single), {
        'artistIds': [1, 2],
        'monitored': true,
        'qualityProfileId': 4,
        'tags': [1],
        'applyTags': 'remove',
      });
    });

    test('none of them sends nothing', () async {
      final harness = Harness();

      await ok(harness.library.bulkEdit([], const BulkEdit(monitored: true)));

      expect(harness.server.requests, isEmpty);
    });

    for (final (name, ref) in [
      ('an album', albumRef(1)),
      ('an artist of another instance', elsewhere),
    ]) {
      test('with $name among them are not changed', () async {
        final harness = Harness();

        await expectProgrammingError(
          () => harness.library.bulkEdit([
            artistRef(1),
            ref,
          ], const BulkEdit(monitored: false)),
        );

        expect(harness.server.requests, isEmpty);
      });
    }
  });

  for (final (name, ref) in [
    ('a track', trackRef(1)),
    ('an artist of another instance', elsewhere),
  ]) {
    test('$name is not edited', () async {
      final harness = Harness();

      await expectProgrammingError(
        () => harness.library.edit(ref, const ItemEdit(monitored: false)),
      );

      expect(harness.server.requests, isEmpty);
    });
  }

  for (final MapEntry(key: cause, value: (answer, expected))
      in writeFailures.entries) {
    test('$cause is reported and the write is sent once', () async {
      final harness = Harness()..server.writeAnswer = answer;

      final failure = await failureOf(
        harness.library.edit(artistRef(1), const ItemEdit(monitored: false)),
      );

      expect(failure.runtimeType, expected);
      expect(harness.server.writes, hasLength(1));
    });
  }
}
