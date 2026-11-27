// Monitoring of authors and books, and applying a monitoring option (story 8,
// as story 5; research R13 for the author).
//
// The options are `MonitorTypes` as the web UI offers them, applied by
// `POST bookshelf`, which is Readarr's name for it and not the fork's.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _options = [
  'all',
  'future',
  'missing',
  'existing',
  'first',
  'latest',
  'none',
];

void main() {
  test('offers the options of Readarr', () {
    expect(
      Harness().library.monitorOptions.map((option) => option.id),
      _options,
    );
  });

  group('monitoring', () {
    for (final monitored in [true, false]) {
      test('sets an author to $monitored, keeping the rest', () async {
        final harness = Harness();
        final before = byId(records('author'), 1);

        await ok(harness.library.setMonitored(author(), monitored));

        expect(harness.asked, [
          line(HttpMethod.get, 'author/1'),
          line(HttpMethod.put, 'author/1'),
        ]);
        expect(sentBody(harness.server.writes.single), {
          ...before,
          'monitored': monitored,
        });
      });

      test('sets a book to $monitored', () async {
        final harness = Harness();

        await ok(harness.library.setMonitored(book(), monitored));

        expect(harness.asked, [line(HttpMethod.put, 'book/monitor')]);
        expect(sentBody(harness.server.writes.single), {
          'bookIds': [8],
          'monitored': monitored,
        });
      });
    }

    for (final (name, target) in [
      ('a movie', movie),
      ('a season', MediaTarget(authorRef(1), seasonNumber: 1)),
      ('an author of another instance', const MediaTarget(elsewhere)),
    ]) {
      test('is not set for $name', () async {
        final harness = Harness();

        await expectProgrammingError(
          () => harness.library.setMonitored(target, true),
        );

        expect(harness.server.requests, isEmpty);
      });
    }

    test('an author that is gone is not written', () async {
      final harness = Harness();
      await ok(harness.library.list());
      harness.server.overrides['author/1'] = FakeReadarr.body('', status: 404);

      expect(
        await failureOf(harness.library.setMonitored(author(), false)),
        isA<NotFound>(),
      );
      expect(harness.server.writes, isEmpty);
      expect(await harness.cache.entry(MediaKind.author, 1), isNull);
    });
  });

  group('monitoring option', () {
    // What the server says of an id it has no author for.
    test('of an author that is gone is not found', () async {
      final harness = Harness();
      await ok(harness.library.list());
      harness.server.writeAnswer = FakeReadarr.body(
        '{"message":"Expected query to return 1 rows but returned 0"}',
        status: 500,
        write: true,
      );

      expect(
        await failureOf(
          harness.library.applyMonitorOption(authorRef(1), 'all'),
        ),
        isA<NotFound>(),
      );
      expect(await harness.cache.entry(MediaKind.author, 1), isNull);
    });

    for (final option in _options) {
      test('applies $option to the author', () async {
        final harness = Harness();

        await ok(harness.library.applyMonitorOption(authorRef(1), option));

        expect(harness.asked, [line(HttpMethod.post, 'bookshelf')]);
        expect(sentBody(harness.server.writes.single), {
          'authors': [
            {'id': 1},
          ],
          'monitoringOptions': {'monitor': option},
        });
      });
    }

    for (final (name, ref, option) in [
      ('to a book', bookRef(8), 'all'),
      ('of another instance', elsewhere, 'all'),
      ('that Readarr does not know', authorRef(1), 'sometimes'),
    ]) {
      test('is not applied $name', () async {
        final harness = Harness();

        await expectProgrammingError(
          () => harness.library.applyMonitorOption(ref, option),
        );

        expect(harness.server.requests, isEmpty);
      });
    }

    for (final MapEntry(key: cause, value: (answer, expected))
        in writeFailures.entries) {
      // A server error is how a missing author reads too.
      if (expected == ServerError) continue;
      test('$cause is reported and sent once', () async {
        final harness = Harness()..server.writeAnswer = answer;

        final failure = await failureOf(
          harness.library.applyMonitorOption(authorRef(1), 'all'),
        );

        expect(failure.runtimeType, expected);
        expect(harness.server.requests, hasLength(1));
      });
    }
  });

  for (final MapEntry(key: cause, value: (answer, expected))
      in writeFailures.entries) {
    test('$cause is reported and monitoring is sent once', () async {
      final harness = Harness()..server.writeAnswer = answer;

      final failure = await failureOf(
        harness.library.setMonitored(book(), true),
      );

      expect(failure.runtimeType, expected);
      expect(harness.server.requests, hasLength(1));
    });
  }
}
