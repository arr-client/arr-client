// Monitoring of a series, a season and an episode, and the season pass (story 5,
// scenarios 1 and 5). Sonarr monitors or unmonitors the episodes of a season
// when the series is written with the season changed.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'manage_support.dart';
import 'support.dart';

/// The recorded series 1 with what no version of the app can know about.
Map<String, Object?> _series() {
  final series = record('manage_series')
    ..['someFutureObject'] = {
      'list': [1, null, 'kept'],
    }
    ..['someFutureNull'] = null;
  for (final season in _seasons(series)) {
    season['someFutureSeasonFlag'] = true;
  }
  return series;
}

List<Map<String, Object?>> _seasons(Map<String, Object?> series) =>
    (series['seasons']! as List<Object?>).cast<Map<String, Object?>>();

ManageHarness _harness() => ManageHarness()..sonarr.item = _series();

/// The monitoring options of Sonarr's own form, as `seasonpass` takes them.
const _options = [
  'all',
  'future',
  'missing',
  'existing',
  'recent',
  'pilot',
  'firstSeason',
  'lastSeason',
  'monitorSpecials',
  'unmonitorSpecials',
  'none',
];

/// Asserts that the series was read and then written whole, with no query.
Object? _written(ManageHarness harness) {
  expect(harness.asked, [
    line(HttpMethod.get, 'series/1'),
    line(HttpMethod.put, 'series/1'),
  ]);
  for (final request in harness.sonarr.requests) {
    expect(request.query, isEmpty);
  }
  return sentBody(harness.sonarr.requests.last);
}

void main() {
  for (final monitored in [true, false]) {
    final to = monitored ? 'on' : 'off';

    test('turns a series $to and nothing else', () async {
      final harness = _harness();
      harness.sonarr.item['monitored'] = !monitored;

      await ok(harness.library.setMonitored(series(), monitored));

      // The seasons go back as they were.
      expect(_written(harness), _series()..['monitored'] = monitored);
    });

    for (final number in [0, 2]) {
      test('turns season $number $to and nothing else', () async {
        final harness = _harness();
        _seasons(harness.sonarr.item)[number]['monitored'] = !monitored;

        await ok(harness.library.setMonitored(season(number), monitored));

        final expected = _series();
        _seasons(expected)[number]['monitored'] = monitored;
        expect(_written(harness), expected);
      });
    }

    test('turns one episode $to without touching the series', () async {
      final harness = _harness();

      await ok(harness.library.setMonitored(episode(), monitored));

      final request = harness.sonarr.requests.single;
      expect(request.method, HttpMethod.put);
      expect(request.path, 'api/v3/episode/monitor');
      expect(request.query, isEmpty);
      expect(sentBody(request), {
        'episodeIds': [31],
        'monitored': monitored,
      });
    });
  }

  for (final (name, change) in <(String, void Function(Map<String, Object?>))>[
    ('has no such season', (series) => _seasons(series).removeLast()),
    ('has no seasons', (series) => series.remove('seasons')),
    ('has seasons of another shape', (series) => series['seasons'] = 'none'),
  ]) {
    test('writes nothing if the series $name', () async {
      final harness = _harness();
      change(harness.sonarr.item);

      await failureOf(harness.library.setMonitored(season(2), false));

      expect(harness.asked, [line(HttpMethod.get, 'series/1')]);
    });
  }

  for (final (name, target) in [
    ('a movie', movie),
    ('an episode of a season', MediaTarget(episodeRef(31), seasonNumber: 1)),
  ]) {
    test('does not monitor $name', () async {
      final harness = _harness();

      await expectProgrammingError(
        () => harness.library.setMonitored(target, false),
      );

      expect(harness.sonarr.requests, isEmpty);
    });
  }

  // A rejected toggle returns, with the reason (scenario 1).
  for (final MapEntry(key: cause, value: (answer, expected))
      in writeFailures.entries) {
    for (final (name, target) in [
      ('series', series()),
      ('season', season(1)),
    ]) {
      test('a $name toggle reports $cause and is sent once', () async {
        final harness = _harness()..sonarr.writeAnswer = answer;

        final failure = await failureOf(
          harness.library.setMonitored(target, false),
        );

        expect(failure.runtimeType, expected);
        expect(harness.asked, [
          line(HttpMethod.get, 'series/1'),
          line(HttpMethod.put, 'series/1'),
        ]);
      });
    }

    test('an episode toggle reports $cause and is sent once', () async {
      final harness = _harness()..sonarr.writeAnswer = answer;

      final failure = await failureOf(
        harness.library.setMonitored(episode(), false),
      );

      expect(failure.runtimeType, expected);
      expect(harness.asked, [line(HttpMethod.put, 'episode/monitor')]);
    });
  }

  test('an episode that is gone is not found', () async {
    final harness = _harness()
      ..sonarr.writeAnswer = FakeSonarr.body(
        '{"message":"Episode with ID 31 does not exist"}',
        status: 404,
        write: true,
      );

    expect(
      await failureOf(harness.library.setMonitored(episode(), true)),
      isA<NotFound>(),
    );
  });

  test('a series that is gone is not written and leaves the cache', () async {
    final harness = _harness();
    await ok(harness.library.list());
    harness.sonarr.requests.clear();
    harness.sonarr.overrides['series/1'] = FakeSonarr.body('', status: 404);

    expect(
      await failureOf(harness.library.setMonitored(season(1), false)),
      isA<NotFound>(),
    );

    expect(harness.asked, [line(HttpMethod.get, 'series/1')]);
    expect(await harness.cachedSeries(), isNot(contains(1)));
  });

  group('monitoring option', () {
    test('offers those of Sonarr without asking the server', () {
      final harness = ManageHarness();

      expect(
        harness.library.monitorOptions.map((option) => option.id),
        _options,
      );
      expect(harness.sonarr.requests, isEmpty);
    });

    for (final option in _options) {
      test('$option goes to the season pass of the one series', () async {
        final harness = ManageHarness();

        await ok(harness.library.applyMonitorOption(seriesRef(1), option));

        // Nothing is read: the server works out what to monitor.
        final request = harness.sonarr.requests.single;
        expect(request.method, HttpMethod.post);
        expect(request.path, 'api/v3/seasonpass');
        expect(request.query, isEmpty);
        expect(sentBody(request), {
          'series': [
            {'id': 1},
          ],
          'monitoringOptions': {'monitor': option},
        });
      });
    }

    for (final option in ['', 'bogus', 'unknown', 'skip', 'All']) {
      test('"$option" is not offered and not sent', () async {
        final harness = ManageHarness();

        await expectProgrammingError(
          () => harness.library.applyMonitorOption(seriesRef(1), option),
        );

        expect(harness.sonarr.requests, isEmpty);
      });
    }

    for (final (name, ref) in [
      ('an episode', episodeRef(31)),
      ('a movie', movie.item),
    ]) {
      test('is not applied to $name', () async {
        final harness = ManageHarness();

        await expectProgrammingError(
          () => harness.library.applyMonitorOption(ref, 'all'),
        );

        expect(harness.sonarr.requests, isEmpty);
      });
    }

    for (final MapEntry(key: cause, value: (answer, expected))
        in writeFailures.entries) {
      test('reports $cause and is sent once', () async {
        final harness = ManageHarness()..sonarr.writeAnswer = answer;

        final failure = await failureOf(
          harness.library.applyMonitorOption(seriesRef(1), 'future'),
        );

        expect(failure.runtimeType, expected);
        expect(harness.asked, [line(HttpMethod.post, 'seasonpass')]);
      });
    }

    test('for a series that is gone says so and forgets it', () async {
      final harness = ManageHarness();
      await ok(harness.library.list());
      harness.sonarr.requests.clear();
      harness.sonarr.writeAnswer = FakeSonarr.body(
        '{"message":"$noSuchSeries"}',
        status: 500,
        write: true,
      );

      expect(
        await failureOf(
          harness.library.applyMonitorOption(seriesRef(1), 'all'),
        ),
        isA<NotFound>(),
      );

      expect(harness.asked, [line(HttpMethod.post, 'seasonpass')]);
      expect(await harness.cachedSeries(), isNot(contains(1)));
    });
  });
}
