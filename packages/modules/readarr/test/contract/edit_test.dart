// Editing authors and books without losing what the app does not know of
// (research R13), and editing several authors at once.
//
// The server writes a book's editions with it and fails without them (500), so
// they are read and sent back as they are, as its web UI does.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('an author', () {
    test('changes only the fields set', () async {
      final harness = Harness();
      byId(harness.server.authors, 1)['unknownToTheApp'] = {'kept': true};
      final before = {...byId(harness.server.authors, 1)};

      await ok(
        harness.library.edit(
          authorRef(1),
          const ItemEdit(
            monitored: false,
            qualityProfileId: 2,
            metadataProfileId: 2,
            tagIds: {},
          ),
        ),
      );

      expect(harness.asked, [
        line(HttpMethod.get, 'author/1'),
        line(HttpMethod.put, 'author/1'),
      ]);
      expect(sentBody(harness.server.writes.single), {
        ...before,
        'monitored': false,
        'qualityProfileId': 2,
        'metadataProfileId': 2,
        'tags': <int>[],
      });
    });

    test('leaves out what an author does not have', () async {
      final harness = Harness();
      final before = {...byId(harness.server.authors, 1)};

      await ok(
        harness.library.edit(
          authorRef(1),
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

  group('a book', () {
    test('keeps its editions and the rest of its record', () async {
      final harness = Harness();
      final before = {...byId(harness.server.books, 8)};

      await ok(
        harness.library.edit(bookRef(8), const ItemEdit(monitored: false)),
      );

      expect(
        harness.asked.take(2),
        unorderedEquals([
          line(HttpMethod.get, 'book/8'),
          line(HttpMethod.get, 'edition'),
        ]),
      );
      expect(harness.asked.skip(2), [line(HttpMethod.put, 'book/8')]);
      expect(sentBody(harness.server.writes.single), {
        ...before,
        'author': byId(records('author'), 1),
        'editions': records('edition_book_8'),
        'monitored': false,
      });
    });

    test('is not written without its editions', () async {
      final harness = Harness();
      harness.server.overrides['edition'] = FakeReadarr.body('', status: 500);

      expect(
        await failureOf(
          harness.library.edit(bookRef(8), const ItemEdit(monitored: false)),
        ),
        isA<ServerError>(),
      );
      expect(harness.server.writes, isEmpty);
    });

    // Its profiles and tags are the author's.
    test('has nothing to write for the fields of an author', () async {
      final harness = Harness();

      await ok(
        harness.library.edit(
          bookRef(8),
          const ItemEdit(
            qualityProfileId: 2,
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

    await ok(harness.library.edit(authorRef(1), const ItemEdit()));

    expect(harness.server.requests, isEmpty);
  });

  group('several authors', () {
    test('are changed by the editor', () async {
      final harness = Harness();

      await ok(
        harness.library.bulkEdit(
          [authorRef(1), authorRef(2)],
          const BulkEdit(
            monitored: true,
            qualityProfileId: 2,
            tagIds: {1},
            tagChange: TagChange.remove,
          ),
        ),
      );

      expect(harness.asked, [line(HttpMethod.put, 'author/editor')]);
      expect(sentBody(harness.server.writes.single), {
        'authorIds': [1, 2],
        'monitored': true,
        'qualityProfileId': 2,
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
      ('a book', bookRef(1)),
      ('an author of another instance', elsewhere),
    ]) {
      test('with $name among them are not changed', () async {
        final harness = Harness();

        await expectProgrammingError(
          () => harness.library.bulkEdit([
            authorRef(1),
            ref,
          ], const BulkEdit(monitored: false)),
        );

        expect(harness.server.requests, isEmpty);
      });
    }
  });

  for (final (name, ref) in [
    (
      'an album',
      const ItemRef(instanceId: instanceId, kind: MediaKind.album, remoteId: 8),
    ),
    ('an author of another instance', elsewhere),
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
        harness.library.edit(authorRef(1), const ItemEdit(monitored: false)),
      );

      expect(failure.runtimeType, expected);
      expect(harness.server.writes, hasLength(1));
    });
  }
}
