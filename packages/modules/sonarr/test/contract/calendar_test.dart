// Sonarr's calendar. The window and the order are the shared Servarr calendar's,
// tested in packages/servarr; here is what Sonarr is asked and what its records
// become.
//
// An episode airs at the instant `airDateUtc`. `airDate` is the day in the
// network's zone, which may not be the day in the device's, so it is not used.
// The tests build their days from the device's zone and hold in any; run them
// with several values of TZ, as CI's UTC cannot tell local time from UTC.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overview_support.dart';
import 'support.dart';

// A window that holds every recorded episode.
final _from = DateTime.utc(2026);
final _to = DateTime.utc(2100);

/// A recorded episode without a file, changed to [changes].
Map<String, Object?> _episode(Map<String, Object?> changes, {int id = 82}) => {
  ...byId(records('overview_calendar'), 82),
  'id': id,
  ...changes,
};

FakeOverview _serving(List<Map<String, Object?>> episodes) => FakeOverview()
  ..calendar.clear()
  ..calendar.addAll(episodes);

Future<List<CalendarEvent>> _events(
  FakeOverview server, {
  DateTime? from,
  DateTime? to,
}) => ok(Harness(server: server).calendar.events(from ?? _from, to ?? _to));

/// The local day [instant] falls on.
DateTime _dayOf(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime _dayAfter(DateTime day, [int days = 1]) =>
    DateTime(day.year, day.month, day.day + days);

void main() {
  test('asks once, with the series of each episode', () async {
    final server = FakeOverview();

    await _events(server);

    final request = server.asked('calendar').single;
    expect(request.method, HttpMethod.get);
    // Besides it, only the queue is needed, for the state.
    expect(server.requests.map((r) => r.path).toSet(), {
      'api/v3/calendar',
      'api/v3/queue',
    });
    expect(server.writes, isEmpty);
    expect(request.query['includeSeries'], ['true']);
    expect(request.query['start']!.single, endsWith('Z'));
    expect(request.query['end']!.single, endsWith('Z'));
  });

  test('each episode is an event, a season released at once too', () async {
    final events = await _events(FakeOverview());

    expect(
      events.map((event) => event.itemRef),
      unorderedEquals([
        for (final id in [40, 41, 42, 43, 44, 45, 46, 47, 81, 82])
          episodeRef(id),
      ]),
    );
    expect(events.map((event) => event.dateKind).toSet(), {
      CalendarDateKind.airDate,
    });
    expect(events.map((event) => event.date), [
      for (var i = 0; i < 8; i++) DateTime.utc(2026, 6, 25, 4),
      DateTime.utc(2026, 9, 16, 4),
      DateTime.utc(2026, 9, 23, 4),
    ]);
    expect(events.every((event) => event.date.isUtc), isTrue);
  });

  test('an event names its series, number and episode', () async {
    final record = _episode({});
    rename(record, 'Slow Horses', 'Signals');

    final events = await _events(_serving([record]));

    expect(events.single.title, titled('Slow Horses', 'S06E02', 'Signals'));
  });

  for (final (season, episode, number) in [
    (0, 3, 'S00E03'),
    (1, 100, 'S01E100'),
    (2026, 5, 'S2026E05'),
  ]) {
    test('numbers an episode $number', () async {
      final record = _episode({
        'seasonNumber': season,
        'episodeNumber': episode,
      });
      rename(record, 'Slow Horses', 'Signals');

      final events = await _events(_serving([record]));

      expect(events.single.title, titled('Slow Horses', number, 'Signals'));
    });
  }

  test('episodes of one season at one time are told apart', () async {
    final events = await _events(FakeOverview());

    expect(events.map((event) => event.title).toSet(), hasLength(10));
  });

  test('names an episode whose series the record lacks', () async {
    final record = _episode({'title': 'Signals'})..remove('series');

    final events = await _events(_serving([record]));

    expect(events.single.title, contains('S06E02'));
    expect(events.single.title, contains('Signals'));
    expect(events.single.title, isNot(contains('null')));
  });

  test('names an episode without a title of its own', () async {
    final record = _episode({})..remove('title');
    record['series'] = {'title': 'Slow Horses'};

    final events = await _events(_serving([record]));

    expect(events.single.title, startsWith('Slow Horses'));
    expect(events.single.title, contains('S06E02'));
    expect(events.single.title, isNot(contains('null')));
  });

  group("in the device's time zone", () {
    // Times of day in UTC that fall on another local day somewhere.
    for (final time in ['00:00', '04:00', '11:30', '18:15', '23:59']) {
      test('an episode at $time UTC is on its local day', () async {
        final aired = DateTime.parse('2026-09-16T$time:00Z');
        final server = _serving([
          // A network day that is far from the instant is not followed.
          _episode({
            'airDate': '2026-01-01',
            'airDateUtc': aired.toIso8601String(),
          }),
        ]);
        final day = _dayOf(aired);

        final on = await _events(server, from: day, to: _dayAfter(day));
        final before = await _events(server, from: _dayAfter(day, -1), to: day);
        final after = await _events(
          server,
          from: _dayAfter(day),
          to: _dayAfter(day, 2),
        );

        expect(on.single.date, aired);
        expect(before, isEmpty);
        expect(after, isEmpty);
      });
    }

    // Days on which clocks change in some zones, and the turn of a year.
    for (final day in [
      DateTime(2026, 3, 8),
      DateTime(2026, 3, 29),
      DateTime(2026, 4, 5),
      DateTime(2026, 9, 6),
      DateTime(2026, 9, 27),
      DateTime(2026, 10, 25),
      DateTime(2026, 11, 1),
      DateTime(2026, 12, 31),
    ]) {
      final name = '${day.year}-${day.month}-${day.day}';
      test('the day $name holds its midnights', () async {
        final next = _dayAfter(day);
        const second = Duration(seconds: 1);
        final server = _serving([
          for (final (id, aired) in [
            (1, day.subtract(second)),
            (2, day),
            (3, next.subtract(second)),
            (4, next),
          ])
            _episode({'airDateUtc': aired.toUtc().toIso8601String()}, id: id),
        ]);

        final events = await _events(server, from: day, to: next);

        expect(events.map((event) => event.itemRef), [
          episodeRef(2),
          episodeRef(3),
        ]);
      });
    }
  });

  test('an episode without a time is not an event', () async {
    // It has a network day only.
    final record = _episode({})..remove('airDateUtc');

    expect(await _events(_serving([record])), isEmpty);
  });

  for (final (name, changes, state) in [
    ('with its file', {'hasFile': true}, ItemState.downloaded),
    ('aired without a file', {'hasFile': false}, ItemState.missing),
    (
      'still to air',
      {'hasFile': false, 'airDateUtc': '2099-01-01T00:00:00Z'},
      ItemState.unreleased,
    ),
  ]) {
    test('an episode $name is ${state.name}', () async {
      final events = await _events(_serving([_episode(changes)]));

      expect(events.single.state, state);
    });
  }

  for (final hasFile in [true, false]) {
    final name = hasFile ? 'with' : 'without';
    test('a queued episode $name a file is downloading', () async {
      final server = _serving([
        _episode({'hasFile': hasFile}),
        _episode({'hasFile': hasFile}, id: 81),
      ])..enqueue(82);

      final events = await _events(server);

      expect(events.map((event) => (event.itemRef, event.state)), [
        (episodeRef(82), ItemState.downloading),
        (episodeRef(81), hasFile ? ItemState.downloaded : ItemState.missing),
      ]);
    });
  }

  // As for the library: a queued episode would otherwise show as missing.
  for (final path in ['queue', 'calendar']) {
    test('fails when the $path cannot be read', () async {
      final server = FakeOverview()..breaks(path);

      expect(
        await failureOf(Harness(server: server).calendar.events(_from, _to)),
        isA<ServerError>(),
      );
      expect(server.asked(path), hasLength(1));
    });
  }

  test('a queue that is not found is a server error', () async {
    final server = FakeOverview()..breaks('queue', status: 404);

    expect(
      await failureOf(Harness(server: server).calendar.events(_from, _to)),
      isA<ServerError>(),
    );
  });

  for (final field in ['id', 'seasonNumber', 'episodeNumber']) {
    test('cannot understand an episode without $field', () async {
      final record = _episode({})..remove(field);
      final harness = Harness(server: _serving([record]));

      expect(
        await failureOf(harness.calendar.events(_from, _to)),
        isA<MalformedResponse>(),
      );
    });
  }

  test('passes a failure on, asking once', () async {
    final server = FakeOverview()..goOffline();

    expect(
      await failureOf(Harness(server: server).calendar.events(_from, _to)),
      isA<Unreachable>(),
    );
    expect(server.requests, hasLength(1));
  });
}
