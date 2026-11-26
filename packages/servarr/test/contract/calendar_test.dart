// The calendar read: `CalendarProvider.events(from, to)` over `GET calendar`.
//
// It holds the events dated from `from` up to, but not including, `to`, oldest
// first. The dates are the ones the module's mapper gives. A movie's dates are
// days, which the module may place anywhere in that day of the device's zone, so
// the server is asked for more than the window and the rest is dropped here.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overview_support.dart';
import 'support.dart';

FakeServer _server(Service service, [List<Object?>? records]) =>
    FakeServer.paths({
      'calendar': records ?? service.fixture('overview_calendar'),
    });

final _from = DateTime.utc(2021, 9);
final _to = DateTime.utc(2027);

/// One record dated [date], as each service writes it.
JsonObject _dated(Service service, int id, String date) {
  final record = service.list('overview_calendar').first
    ..['id'] = id
    ..remove('inCinemas')
    ..remove('digitalRelease')
    ..remove('physicalRelease')
    ..remove('airDateUtc');
  record[service == radarr ? 'digitalRelease' : 'airDateUtc'] = date;
  return record;
}

Future<List<CalendarEvent>> _events(
  Service service, {
  required DateTime from,
  required DateTime to,
  List<Object?>? records,
}) => value(service.calendar(_server(service, records)).events(from, to));

void main() {
  for (final service in services) {
    group('${service.name} calendar', () {
      test('asks once, for more than the window, in UTC', () async {
        final server = _server(service);
        // Local times, as the app has them.
        final from = DateTime(2026, 9, 14);
        final to = DateTime(2026, 9, 21);

        await value(service.calendar(server).events(from, to));

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/calendar');
        expect(request.body, isNull);
        expect(
          request.query.keys,
          containsAll(['start', 'end', ...service.itemQuery.keys]),
        );
        for (final MapEntry(:key, :value) in service.itemQuery.entries) {
          expect(request.query[key], value);
        }
        final start = request.query['start']!.single;
        final end = request.query['end']!.single;
        expect(start, endsWith('Z'));
        expect(end, endsWith('Z'));
        // Zones reach from 12 hours behind UTC to 14 ahead of it.
        expect(
          DateTime.parse(start)
              .isAfter(from.subtract(const Duration(hours: 14))),
          isFalse,
        );
        expect(
          DateTime.parse(end).isBefore(to.add(const Duration(hours: 14))),
          isFalse,
        );
      });

      test('maps the recorded releases, oldest first', () async {
        final events = await _events(service, from: _from, to: _to);

        expect(
          events.map(
            (event) => (event.itemRef.remoteId, event.dateKind, event.date),
          ),
          service == radarr
              ? [
                  (1, CalendarDateKind.inCinemas, DateTime.utc(2021, 9, 15)),
                  (
                    1,
                    CalendarDateKind.digitalRelease,
                    DateTime.utc(2021, 10, 21),
                  ),
                  (
                    1,
                    CalendarDateKind.physicalRelease,
                    DateTime.utc(2021, 12, 22),
                  ),
                  (2, CalendarDateKind.inCinemas, DateTime.utc(2024, 2, 27)),
                  (
                    2,
                    CalendarDateKind.digitalRelease,
                    DateTime.utc(2024, 4, 15),
                  ),
                  (
                    2,
                    CalendarDateKind.physicalRelease,
                    DateTime.utc(2024, 5, 14),
                  ),
                  (3, CalendarDateKind.inCinemas, DateTime.utc(2026, 12, 15)),
                ]
              : [
                  (34, CalendarDateKind.airDate, DateTime.utc(2026, 9, 16, 4)),
                  (35, CalendarDateKind.airDate, DateTime.utc(2026, 9, 23, 4)),
                  (36, CalendarDateKind.airDate, DateTime.utc(2026, 9, 30, 4)),
                  (37, CalendarDateKind.airDate, DateTime.utc(2026, 10, 7, 4)),
                ],
        );
      });

      test('orders by date, not as the server answers', () async {
        final records = service.list('overview_calendar').reversed.toList();

        final events = await _events(
          service,
          from: _from,
          to: _to,
          records: records,
        );

        final dates = [for (final event in events) event.date];
        expect(dates, [...dates]..sort());
        expect(dates, hasLength(service == radarr ? 7 : 4));
      });

      test('holds the start of the window but not its end', () async {
        final from = DateTime.utc(2026, 9, 14);
        final to = DateTime.utc(2026, 9, 21);
        const second = Duration(seconds: 1);
        final records = [
          for (final (id, date) in [
            (1, from.subtract(second)),
            (2, from),
            (3, to.subtract(second)),
            (4, to),
          ])
            _dated(service, id, date.toIso8601String()),
        ];

        final events = await _events(
          service,
          from: from,
          to: to,
          records: records,
        );

        expect(events.map((event) => event.itemRef.remoteId), [2, 3]);
      });

      test('compares instants when the window is in local time', () async {
        final from = DateTime(2026, 9, 14);
        final to = DateTime(2026, 9, 15);
        const second = Duration(seconds: 1);
        final records = [
          for (final (id, date) in [
            (1, from.subtract(second)),
            (2, from),
            (3, to.subtract(second)),
            (4, to),
          ])
            _dated(service, id, date.toUtc().toIso8601String()),
        ];

        final events = await _events(
          service,
          from: from,
          to: to,
          records: records,
        );

        expect(events.map((event) => event.itemRef.remoteId), [2, 3]);
      });

      test('keeps the window by the dates the mapper gives', () async {
        // As a module might place a day in a zone behind UTC: the server's
        // midnight is before the window, the day is in it.
        final from = DateTime.utc(2026, 9, 14, 5);
        final server = _server(service, [
          _dated(service, 1, '2026-09-14T00:00:00Z'),
        ]);
        final calendar = service.calendar(
          server,
          events: (record) => [
            CalendarEvent(
              itemRef: service.itemOf(record['id']! as int),
              title: 'Title',
              date: from,
              dateKind: CalendarDateKind.digitalRelease,
              state: ItemState.missing,
            ),
          ],
        );

        final events = await value(
          calendar.events(from, from.add(const Duration(days: 1))),
        );

        expect(events.single.date, from);
      });

      test('leaves out a record without a date', () async {
        final record = _dated(service, 1, '2026-09-14T00:00:00Z')
          ..remove('digitalRelease')
          ..remove('airDateUtc');

        expect(
          await _events(service, from: _from, to: _to, records: [record]),
          isEmpty,
        );
      });

      test('is empty when nothing is coming', () async {
        expect(
          await _events(service, from: _from, to: _to, records: []),
          isEmpty,
        );
      });

      test('passes a failure on, asking once', () async {
        final server = FakeServer.always(const NoReply(Unreachable()));

        expect(
          await failure(service.calendar(server).events(_from, _to)),
          isA<Unreachable>(),
        );
        expect(server.requests, hasLength(1));
      });

      for (final (name, body) in [
        ('an object', <String, Object?>{}),
        ('a list of texts', ['no']),
      ]) {
        test('cannot understand $name', () async {
          final server = FakeServer.paths({'calendar': body});

          expect(
            await failure(service.calendar(server).events(_from, _to)),
            isA<MalformedResponse>(),
          );
        });
      }

      test('cannot understand what the mapper cannot', () async {
        final calendar = service.calendar(
          _server(service),
          events: (_) => throw const FormatException('No'),
        );

        expect(
          await failure(calendar.events(_from, _to)),
          isA<MalformedResponse>(),
        );
      });
    });
  }
}
