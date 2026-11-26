// Monitoring of artists and albums, and applying a monitoring option
// (story 8, as story 5; research R13 for the artist).
//
// The options are `MonitorTypes` as Lidarr's web UI offers them, applied by
// `POST albumstudio`. A track follows its album.

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
  test('offers the options of Lidarr', () {
    expect(
      Harness().library.monitorOptions.map((option) => option.id),
      _options,
    );
  });

  group('monitoring', () {
    for (final monitored in [true, false]) {
      test('sets an artist to $monitored, keeping the rest', () async {
        final harness = Harness();
        final before = byId(records('artist'), 1);

        await ok(harness.library.setMonitored(artist(), monitored));

        expect(harness.asked, [
          line(HttpMethod.get, 'artist/1'),
          line(HttpMethod.put, 'artist/1'),
        ]);
        expect(sentBody(harness.server.writes.single), {
          ...before,
          'monitored': monitored,
        });
      });

      test('sets an album to $monitored', () async {
        final harness = Harness();

        await ok(harness.library.setMonitored(album(2), monitored));

        expect(harness.asked, [line(HttpMethod.put, 'album/monitor')]);
        expect(sentBody(harness.server.writes.single), {
          'albumIds': [2],
          'monitored': monitored,
        });
      });
    }

    for (final (name, target) in [
      ('a track', track()),
      ('a movie', movie),
      ('a season', MediaTarget(artistRef(1), seasonNumber: 1)),
      ('an artist of another instance', const MediaTarget(elsewhere)),
    ]) {
      test('is not set for $name', () async {
        final harness = Harness();

        await expectProgrammingError(
          () => harness.library.setMonitored(target, true),
        );

        expect(harness.server.requests, isEmpty);
      });
    }

    test('an artist that is gone is not written', () async {
      final harness = Harness();
      await ok(harness.library.list());
      harness.server.overrides['artist/1'] = FakeLidarr.body('', status: 404);

      expect(
        await failureOf(harness.library.setMonitored(artist(), false)),
        isA<NotFound>(),
      );
      expect(harness.server.writes, isEmpty);
      expect(await harness.cache.entry(MediaKind.artist, 1), isNull);
    });
  });

  group('monitoring option', () {
    // What the server says of an id it has no artist for.
    test('of an artist that is gone is not found', () async {
      final harness = Harness();
      await ok(harness.library.list());
      harness.server.writeAnswer = FakeLidarr.body(
        '{"message":"Expected query to return 1 rows but returned 0"}',
        status: 500,
        write: true,
      );

      expect(
        await failureOf(
          harness.library.applyMonitorOption(artistRef(1), 'all'),
        ),
        isA<NotFound>(),
      );
      expect(await harness.cache.entry(MediaKind.artist, 1), isNull);
    });

    for (final option in _options) {
      test('applies $option to the artist', () async {
        final harness = Harness();

        await ok(harness.library.applyMonitorOption(artistRef(1), option));

        expect(harness.asked, [line(HttpMethod.post, 'albumstudio')]);
        expect(sentBody(harness.server.writes.single), {
          'artist': [
            {'id': 1},
          ],
          'monitoringOptions': {'monitor': option},
        });
      });
    }

    for (final (name, ref, option) in [
      ('to an album', albumRef(1), 'all'),
      ('of another instance', elsewhere, 'all'),
      ('that Lidarr does not know', artistRef(1), 'sometimes'),
    ]) {
      test('is not applied $name', () async {
        final harness = Harness();

        await expectProgrammingError(
          () => harness.library.applyMonitorOption(ref, option),
        );

        expect(harness.server.requests, isEmpty);
      });
    }
  });

  for (final MapEntry(key: cause, value: (answer, expected))
      in writeFailures.entries) {
    test('$cause is reported and sent once', () async {
      final harness = Harness()..server.writeAnswer = answer;

      final failure = await failureOf(
        harness.library.setMonitored(album(2), true),
      );

      expect(failure.runtimeType, expected);
      expect(harness.server.requests, hasLength(1));
    });
  }
}
