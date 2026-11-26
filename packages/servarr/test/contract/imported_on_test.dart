// "Downloaded today": `CalendarProvider.importedOn(day)` over
// `GET history/since` (spec story 6 scenario 5, FR-026).
//
// The day is the year, month and day of `day`, in the device's zone: from its
// local midnight up to the next one, which is 23 or 25 hours on when the clocks
// change. `startOfDay` gives the first instant of a day and is
// `DateTime(year, month, day)` unless a test puts another zone in its place; it
// may be asked for day 32 and the like, as `DateTime` may. Only imports are
// listed, each item once with its latest import of that day, newest first.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overview_support.dart';
import 'support.dart';

/// Answers as `history/since` does: oldest first, whatever the `date`.
FakeServer _server(List<Object?> records) =>
    FakeServer.paths({'history/since': records});

const _second = Duration(seconds: 1);

/// A zone known by the instants its days begin at, in UTC.
DateTime Function(int, int, int) _zone(
  Map<(int, int, int), DateTime> midnights,
) => (year, month, day) {
  final date = DateTime.utc(year, month, day);
  return midnights[(date.year, date.month, date.day)] ??
      (throw StateError('No midnight given for $date'));
};

/// A day in a zone: the day asked for, when it begins and when the next does.
class _Day {
  const _Day(this.name, this.day, this.start, this.end);

  final String name;
  final DateTime day;
  final DateTime start;
  final DateTime end;

  DateTime Function(int, int, int) get startOfDay => _zone({
    (day.year, day.month, day.day): start,
    () {
      final next = DateTime.utc(day.year, day.month, day.day + 1);
      return (next.year, next.month, next.day);
    }(): end,
  });
}

final _days = [
  _Day(
    'far ahead of UTC (Auckland)',
    DateTime(2026, 11, 26),
    DateTime.utc(2026, 11, 25, 11),
    DateTime.utc(2026, 11, 26, 11),
  ),
  _Day(
    'behind UTC (New York)',
    DateTime(2026, 11, 26),
    DateTime.utc(2026, 11, 26, 5),
    DateTime.utc(2026, 11, 27, 5),
  ),
  _Day(
    'at a quarter hour (Kathmandu)',
    DateTime(2026, 11, 26),
    DateTime.utc(2026, 11, 25, 18, 15),
    DateTime.utc(2026, 11, 26, 18, 15),
  ),
  _Day(
    'of 23 hours (London, clocks forward)',
    DateTime(2026, 3, 29),
    DateTime.utc(2026, 3, 29),
    DateTime.utc(2026, 3, 29, 23),
  ),
  _Day(
    'of 25 hours (London, clocks back)',
    DateTime(2026, 10, 25),
    DateTime.utc(2026, 10, 24, 23),
    DateTime.utc(2026, 10, 26),
  ),
  _Day(
    'without a midnight (Santiago)',
    DateTime(2026, 9, 6),
    DateTime.utc(2026, 9, 6, 4),
    DateTime.utc(2026, 9, 7, 3),
  ),
  _Day(
    'at the end of a year',
    DateTime(2026, 12, 31),
    DateTime.utc(2026, 12, 31),
    DateTime.utc(2027),
  ),
];

/// The day of the recorded imports, as UTC has it.
final _recordedDay = DateTime(2026, 11, 26);

final _utc = _zone({
  (2026, 11, 25): DateTime.utc(2026, 11, 25),
  (2026, 11, 26): DateTime.utc(2026, 11, 26),
  (2026, 11, 27): DateTime.utc(2026, 11, 27),
});

Future<List<ImportedItem>> _importedOn(
  Service service,
  List<Object?> records, {
  DateTime? day,
  DateTime Function(int, int, int)? startOfDay,
}) => value(
  service
      .calendar(_server(records), startOfDay: startOfDay ?? _utc)
      .importedOn(day ?? _recordedDay),
);

void main() {
  for (final service in services) {
    // The recorded items: movies 1 and 4, episodes 34 and 35. The first was
    // imported twice, the second import an upgrade.
    final first = service == radarr ? 1 : 34;
    final other = service == radarr ? 4 : 35;

    group('${service.name} imported on a day', () {
      test('asks once for the imports since before that day', () async {
        final server = _server(service.list('overview_history_since'));

        await value(
          service.calendar(server, startOfDay: _utc).importedOn(_recordedDay),
        );

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/history/since');
        expect(request.body, isNull);
        expect(
          request.query['eventType']!.single,
          anyOf('3', 'downloadFolderImported'),
        );
        for (final MapEntry(:key, :value) in service.historyQuery.entries) {
          expect(request.query[key], value);
        }
      });

      for (final day in _days) {
        test('asks from just before a day ${day.name}', () async {
          final server = _server([]);

          await value(
            service
                .calendar(server, startOfDay: day.startOfDay)
                .importedOn(day.day),
          );

          final asked = server.requests.single.query['date']!.single;
          // Radarr misreads an offset.
          expect(asked, endsWith('Z'));
          final since = DateTime.parse(asked);
          expect(since.isAfter(day.start.subtract(_second)), isFalse);
          expect(
            since.isBefore(day.start.subtract(const Duration(days: 1))),
            isFalse,
          );
        });

        test('holds the midnights of a day ${day.name}', () async {
          final records = [
            for (final (id, date) in [
              (1, day.start.subtract(_second)),
              (2, day.start),
              (3, day.end.subtract(_second)),
              (4, day.end),
              (5, day.end.add(const Duration(days: 2))),
            ])
              service.import(1, date: date, newId: id, item: id),
          ];

          final imported = await _importedOn(
            service,
            records,
            day: day.day,
            startOfDay: day.startOfDay,
          );

          expect(imported.map((item) => item.itemRef), [
            service.itemOf(3),
            service.itemOf(2),
          ]);
          expect(imported.map((item) => item.importedAt), [
            day.end.subtract(_second),
            day.start,
          ]);
        });
      }

      test('takes the day, not the time of day', () async {
        final records = [
          service.import(1, date: DateTime.utc(2026, 11, 26, 0, 0, 1)),
        ];

        final imported = await _importedOn(
          service,
          records,
          day: DateTime(2026, 11, 26, 23, 59, 59),
        );

        expect(imported, hasLength(1));
      });

      test('goes back to an earlier day', () async {
        final records = [
          service.import(1, date: DateTime.utc(2026, 11, 25, 20), item: 7),
          service.import(2, date: DateTime.utc(2026, 11, 26, 20), item: 8),
        ];

        final imported = await _importedOn(
          service,
          records,
          day: DateTime(2026, 11, 25),
        );

        expect(imported.single.itemRef, service.itemOf(7));
      });

      // Holds in whatever zone the test runs.
      test('uses the local midnights of the device by default', () async {
        final start = DateTime(2026, 11, 26);
        final end = DateTime(2026, 11, 27);
        final server = _server([
          for (final (id, date) in [
            (1, start.subtract(_second)),
            (2, start),
            (3, end.subtract(_second)),
            (4, end),
          ])
            service.import(1, date: date, newId: id, item: id),
        ]);

        final imported = await value(
          service.calendar(server).importedOn(start),
        );

        expect(imported.map((item) => item.itemRef), [
          service.itemOf(3),
          service.itemOf(2),
        ]);
        expect(
          DateTime.parse(server.requests.single.query['date']!.single)
              .isBefore(start),
          isTrue,
        );
      });

      test(
        'lists the recorded imports, newest first, each item once',
        () async {
          final records = service.list('overview_history_since');

          final imported = await _importedOn(service, records);

          expect(imported.map((item) => item.itemRef), [
            service.itemOf(first),
            service.itemOf(other),
          ]);
          expect(
            imported.map((item) => item.importedAt),
            service == radarr
                ? [
                    DateTime.utc(2026, 11, 26, 13, 55, 41),
                    DateTime.utc(2026, 11, 26, 13, 55, 37),
                  ]
                : [
                    DateTime.utc(2026, 11, 26, 13, 55, 53),
                    DateTime.utc(2026, 11, 26, 13, 55, 49),
                  ],
          );
          expect(imported.every((item) => item.importedAt.isUtc), isTrue);
          // The upgrade's quality, not the first one's.
          expect(
            imported.map((item) => (item.quality?.id, item.quality?.name)),
            [(15, 'WEBRip-1080p'), (7, 'Bluray-1080p')],
          );
          expect(imported.map((item) => item.title), [
            service.importTitle(records.last),
            service.importTitle(records[1]),
          ]);
        },
      );

      test('does not depend on the order of the answer', () async {
        final records = service.list('overview_history_since');

        final imported = await _importedOn(service, records.reversed.toList());

        expect(imported.map((item) => item.itemRef), [
          service.itemOf(first),
          service.itemOf(other),
        ]);
        expect(imported.first.quality?.name, 'WEBRip-1080p');
      });

      // The server answers with whole seconds; the id orders those of one.
      for (final reversed in [false, true]) {
        final order = reversed ? 'newest' : 'oldest';
        test('takes the later of two in one second, $order first', () async {
          final noon = DateTime.utc(2026, 11, 26, 12);
          final records = [
            service.import(1, date: noon, item: 9),
            service.import(4, date: noon, item: 9),
          ];

          final imported = await _importedOn(
            service,
            reversed ? records.reversed.toList() : records,
          );

          expect(imported.single.quality?.name, 'WEBRip-1080p');
        });
      }

      test('takes the latest import of the day itself', () async {
        final noon = DateTime.utc(2026, 11, 26, 12);
        final records = [
          service.import(1, date: noon, newId: 1, item: 9),
          // The same item upgraded the next day.
          service.import(4, date: noon.add(const Duration(days: 1)), item: 9),
        ];

        final imported = await _importedOn(service, records);

        expect(imported.single.importedAt, noon);
        expect(imported.single.quality?.name, 'WEBDL-720p');
      });

      for (final type in [
        'grabbed',
        'downloadFailed',
        'downloadIgnored',
        if (service == radarr) ...['movieFileDeleted', 'movieFileRenamed'],
        if (service == sonarr) ...['episodeFileDeleted', 'episodeFileRenamed'],
      ]) {
        test('does not list a $type event', () async {
          final record = service.import(1, date: DateTime.utc(2026, 11, 26, 12))
            ..['eventType'] = type;

          expect(await _importedOn(service, [record]), isEmpty);
        });
      }

      test('does not merge imports the server cannot match', () async {
        final records = [
          for (final id in [1, 2])
            service.import(id, date: DateTime.utc(2026, 11, 26, 12, id))
              ..remove(service == radarr ? 'movieId' : 'episodeId')
              ..remove('movie')
              ..remove('episode'),
        ];

        final imported = await _importedOn(service, records);

        expect(imported.map((item) => item.itemRef), [null, null]);
      });

      test('lists an import without a quality', () async {
        final record = service.import(1, date: DateTime.utc(2026, 11, 26, 12))
          ..remove('quality');

        final imported = await _importedOn(service, [record]);

        expect(imported.single.quality, isNull);
      });

      test('is empty on a day without imports', () async {
        expect(await _importedOn(service, []), isEmpty);
      });

      test('passes a failure on, asking once', () async {
        final server = FakeServer.always(const NoReply(Unreachable()));

        expect(
          await failure(
            service.calendar(server, startOfDay: _utc).importedOn(_recordedDay),
          ),
          isA<Unreachable>(),
        );
        expect(server.requests, hasLength(1));
      });

      for (final field in ['date', 'id']) {
        test('cannot understand an import without $field', () async {
          final records = service.list('overview_history_since');
          records.first.remove(field);

          expect(
            await failure(
              service
                  .calendar(_server(records), startOfDay: _utc)
                  .importedOn(_recordedDay),
            ),
            isA<MalformedResponse>(),
          );
        });
      }

      test('cannot understand an answer that is not a list', () async {
        final server = FakeServer.paths({'history/since': <String, Object?>{}});

        expect(
          await failure(
            service.calendar(server, startOfDay: _utc).importedOn(_recordedDay),
          ),
          isA<MalformedResponse>(),
        );
      });
    });
  }
}
