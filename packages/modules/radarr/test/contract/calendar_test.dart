// Radarr's releases (spec story 6, FR-024).
//
// A movie has up to three release dates, each its own event. Radarr writes them
// as midnight UTC, but they are days, not instants: the event's date is local
// midnight of the day written, `DateTime(year, month, day)`. Passed on as the
// instant, it would be shown as the day before anywhere west of UTC.
//
// An `isUtc` date fails these tests in any zone. A conversion with `toLocal()`
// only fails where the zone is not UTC, so run them under others too:
//
//   TZ=America/New_York flutter test test/contract/calendar_test.dart
//   TZ=Pacific/Auckland flutter test test/contract/calendar_test.dart

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';
import 'overview_support.dart';

Harness _harness([List<Map<String, Object?>>? movies]) =>
    Harness()..serve('calendar', movies ?? fixture('overview_calendar'));

final _from = DateTime(2000);
final _to = DateTime(2028);

Future<List<CalendarEvent>> _events(
  Harness harness, {
  DateTime? from,
  DateTime? to,
}) => succeed(harness.calendar.events(from ?? _from, to ?? _to));

/// The recorded movie [id].
Map<String, Object?> _movie(int id) => recorded('overview_calendar', id);

/// Movie 1 with [changes] and no release dates but those in them.
Map<String, Object?> _undated([Map<String, Object?> changes = const {}]) => {
  ..._movie(1)
    ..remove('inCinemas')
    ..remove('digitalRelease')
    ..remove('physicalRelease')
    ..remove('releaseDate'),
  ...changes,
};

(int, CalendarDateKind, DateTime) _summary(CalendarEvent event) =>
    (event.itemRef.remoteId, event.dateKind, event.date);

const _cinema = CalendarDateKind.inCinemas;
const _digital = CalendarDateKind.digitalRelease;
const _physical = CalendarDateKind.physicalRelease;

/// Every release in the recording.
final _recorded = [
  (4, _cinema, DateTime(2008, 4, 10)),
  (4, _digital, DateTime(2008, 4, 10)),
  (7, _cinema, DateTime(2015, 9, 30)),
  (7, _digital, DateTime(2015, 12, 22)),
  (7, _physical, DateTime(2016, 1, 12)),
  (5, _cinema, DateTime(2016, 11, 10)),
  (5, _physical, DateTime(2017, 2, 14)),
  (5, _digital, DateTime(2017, 4, 7)),
  (6, _cinema, DateTime(2017, 10, 4)),
  (6, _digital, DateTime(2017, 12, 26)),
  (6, _physical, DateTime(2018, 1, 16)),
  (1, _cinema, DateTime(2021, 9, 15)),
  (1, _digital, DateTime(2021, 10, 21)),
  (1, _physical, DateTime(2021, 12, 22)),
  (2, _cinema, DateTime(2024, 2, 27)),
  (2, _digital, DateTime(2024, 4, 15)),
  (2, _physical, DateTime(2024, 5, 14)),
  (3, _cinema, DateTime(2026, 12, 15)),
];

void main() {
  test('asks for the calendar once, around the window, in UTC', () async {
    final harness = _harness();
    final from = DateTime(2026, 9, 14);
    final to = DateTime(2026, 9, 21);

    await _events(harness, from: from, to: to);

    final request = harness.asked('calendar').single;
    expect(request.method, HttpMethod.get);
    expect(request.body, isNull);
    final start = request.query['start']!.single;
    final end = request.query['end']!.single;
    expect(start, endsWith('Z'));
    expect(end, endsWith('Z'));
    expect(DateTime.parse(start).isBefore(from), isTrue);
    expect(DateTime.parse(end).isAfter(to), isTrue);
    // Besides it, only the queue is needed, for the state.
    expect(
      harness.server.requests.map((r) => r.path).toSet(),
      everyElement(anyOf('api/v3/calendar', 'api/v3/queue')),
    );
    expect(harness.server.requests.map((r) => r.method).toSet(), {
      HttpMethod.get,
    });
  });

  test('has an event for each release date, oldest first', () async {
    final events = await _events(_harness());

    expect(events.map(_summary), unorderedEquals(_recorded));
    final dates = [for (final event in events) event.date];
    expect(dates, [...dates]..sort());
  });

  test('names the movie of each event', () async {
    final events = await _events(_harness());

    for (final event in events) {
      expect(event.itemRef, movieRef(event.itemRef.remoteId));
      expect(event.title, _movie(event.itemRef.remoteId)['title']);
    }
  });

  group('a release date', () {
    test('is local midnight of its day, not an instant in UTC', () async {
      final events = await _events(_harness());

      expect(events, isNotEmpty);
      for (final event in events) {
        expect(event.date.isUtc, isFalse);
        expect(
          event.date,
          DateTime(event.date.year, event.date.month, event.date.day),
        );
      }
    });

    for (final (name, wire, day) in [
      ('a month', '2026-03-01T00:00:00Z', DateTime(2026, 3)),
      ('a year', '2027-01-01T00:00:00Z', DateTime(2027)),
      // Days on which some zones change their clocks, one at midnight.
      ('spring', '2026-03-29T00:00:00Z', DateTime(2026, 3, 29)),
      ('autumn', '2026-09-06T00:00:00Z', DateTime(2026, 9, 6)),
    ]) {
      test('keeps its day at the start of $name', () async {
        final harness = _harness([
          _undated({'digitalRelease': wire}),
        ]);

        final events = await _events(harness);

        expect(events.single.date, day);
      });
    }

    test('is in the window of its own local day only', () async {
      Future<List<(int, CalendarDateKind, DateTime)>> on(DateTime day) async {
        final events = await _events(
          _harness(),
          from: day,
          to: DateTime(day.year, day.month, day.day + 1),
        );
        return events.map(_summary).toList();
      }

      expect(await on(DateTime(2021, 9, 14)), isEmpty);
      expect(await on(DateTime(2021, 9, 15)), [
        (1, _cinema, DateTime(2021, 9, 15)),
      ]);
      expect(await on(DateTime(2021, 9, 16)), isEmpty);
    });

    // `releaseDate` is the server's pick among the three, not a fourth.
    test('is not taken from releaseDate', () async {
      final harness = _harness([
        _undated({'releaseDate': '2021-09-15T00:00:00Z'}),
      ]);

      expect(await _events(harness), isEmpty);
    });

    for (final (name, value) in <(String, Object?)>[
      ('null', null),
      ('empty', ''),
      ('not a date', 'soon'),
      ('not a text', 2021),
    ]) {
      test('is left out when $name', () async {
        final harness = _harness([
          _undated({
            'inCinemas': value,
            'digitalRelease': '2021-10-21T00:00:00Z',
          }),
        ]);

        final events = await _events(harness);

        expect(events.map(_summary), [(1, _digital, DateTime(2021, 10, 21))]);
      });
    }
  });

  group('the state of an event', () {
    Future<Map<int, ItemState>> states(Harness harness) async => {
      for (final event in await _events(harness))
        event.itemRef.remoteId: event.state,
    };

    test('is that of the movie', () async {
      expect(await states(_harness()), {
        1: ItemState.downloaded,
        2: ItemState.missing,
        3: ItemState.missing,
        4: ItemState.downloaded,
        5: ItemState.missing,
        6: ItemState.downloaded,
        7: ItemState.downloaded,
      });
    });

    test('follows what the server says about the movie', () async {
      final harness = _harness([
        {..._movie(2), 'isAvailable': false},
        {..._movie(5), 'monitored': false},
      ]);

      expect(await states(harness), {
        2: ItemState.unreleased,
        5: ItemState.unmonitored,
      });
    });

    test('is downloading for a queued movie', () async {
      for (final id in [1, 5]) {
        final harness = _harness()..enqueue(id);

        final found = await states(harness);

        expect(found[id], ItemState.downloading);
        expect(found[2], ItemState.missing);
      }
    });
  });

  test('is empty when nothing is coming', () async {
    expect(await _events(_harness([])), isEmpty);
  });

  test('does not need a movie to have any date', () async {
    expect(await _events(_harness([_undated()])), isEmpty);
  });

  test('passes a failure on', () async {
    final harness = _harness()..server.down = failedAnswer(const Unreachable());

    expect(
      await failureOf(harness.calendar.events(_from, _to)),
      isA<Unreachable>(),
    );
    expect(harness.asked('calendar').length, lessThanOrEqualTo(1));
  });

  // As for the library: a queued movie would otherwise show as missing.
  test('fails when the queue cannot be read', () async {
    final harness = _harness()
      ..server.answers['api/v3/queue'] = failedAnswer(
        const ServerError(statusCode: 500),
        status: 500,
      );

    expect(
      await failureOf(harness.calendar.events(_from, _to)),
      isA<ServerError>(),
    );
  });

  for (final (name, body) in <(String, Object?)>[
    ('an object', <String, Object?>{}),
    ('a list of texts', ['no']),
    ('a movie without an id', [_movie(1)..remove('id')]),
    ('a movie without a title', [_movie(1)..remove('title')]),
  ]) {
    test('cannot understand $name', () async {
      final harness = Harness()..serve('calendar', body);

      expect(
        await failureOf(harness.calendar.events(_from, _to)),
        isA<MalformedResponse>(),
      );
    });
  }
}
