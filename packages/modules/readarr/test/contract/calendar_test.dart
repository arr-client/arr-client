// The calendar of book releases, and what was imported (story 8, scenario 4, as
// story 6).
//
// Readarr's import event is `bookFileImported`, number 3 of its
// `EntityHistoryEventType`. The shared calendar takes the word the services for
// movies and series have by default.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _from = DateTime.utc(1890);
final _to = DateTime.utc(1912);

Future<Map<ItemRef, CalendarEvent>> _events(Harness harness) async => {
  for (final event in await ok(harness.calendar.events(_from, _to)))
    event.itemRef: event,
};

/// The latest recorded import of [book].
Map<String, Object?> _latestImport(int book) =>
    pageRecords('overview_history_imports')
        .firstWhere((record) => record['bookId'] == book);

String _name(Map<String, Object?> raw, String of, String field) =>
    (raw[of]! as Map<String, Object?>)[field]! as String;

void main() {
  group('events', () {
    test('the monitored books released in the range, by date', () async {
      final harness = Harness();

      final events = await ok(harness.calendar.events(_from, _to));

      expect(events.map((event) => event.itemRef), [
        for (final id in [18, 29, 1, 8, 10, 19]) bookRef(id),
      ]);
      final request = harness.server.requests.singleWhere(
        (request) => request.path == 'api/v1/calendar',
      );
      expect(request.query['includeAuthor'], ['true']);
      expect(request.query['unmonitored'], anyOf(isNull, ['false']));
      expect(
        DateTime.parse(request.query['start']!.single).isAfter(_from),
        isFalse,
      );
      expect(
        DateTime.parse(request.query['end']!.single).isBefore(_to),
        isFalse,
      );
    });

    test('maps a release with its author', () async {
      final harness = Harness();
      final raw = byId(records('overview_calendar'), 8);

      final event = (await _events(harness))[bookRef(8)]!;

      expect(event.date, DateTime.parse(raw['releaseDate']! as String));
      expect(event.dateKind, CalendarDateKind.releaseDate);
      expect(event.title, contains(raw['title']! as String));
      expect(event.title, contains(_name(raw, 'author', 'authorName')));
    });

    test('keeps only the releases of the range', () async {
      final events = await ok(
        Harness().calendar.events(DateTime.utc(1904), DateTime.utc(1908)),
      );

      expect(events.map((event) => event.itemRef), [
        for (final id in [29, 1, 8]) bookRef(id),
      ]);
    });

    test('states follow the statistics and the queue', () async {
      final queued = await _events(Harness());
      final idle = await _events(Harness()..server.queue.clear());

      expect(queued[bookRef(19)]!.state, ItemState.downloading);
      expect(queued[bookRef(8)]!.state, ItemState.downloaded);
      expect(idle[bookRef(19)]!.state, ItemState.missing);
    });

    test('fail when the queue cannot be read', () async {
      final harness = Harness();
      harness.server.overrides['queue'] = FakeReadarr.body('', status: 500);

      expect(
        await failureOf(harness.calendar.events(_from, _to)),
        isA<ServerError>(),
      );
    });

    test('skip a book without a release date', () async {
      final harness = Harness();
      byId(harness.server.calendar, 8).remove('releaseDate');

      expect((await _events(harness)).keys, isNot(contains(bookRef(8))));
    });
  });

  group('recently added', () {
    test('asks for imports with their author and book', () async {
      final harness = Harness();

      await ok(harness.calendar.recentlyAdded());

      expect(harness.asked, [line(HttpMethod.get, 'history')]);
      final query = harness.server.requests.single.query;
      expect(query['eventType'], ['3']);
      expect(query['includeAuthor'], ['true']);
      expect(query['includeBook'], ['true']);
      expect(query['sortDirection'], ['descending']);
    });

    test('each book once, with its latest import', () async {
      final items = await ok(Harness().calendar.recentlyAdded());

      expect(items.map((item) => item.itemRef), [
        for (final id in [29, 18, 10, 8]) bookRef(id),
      ]);
      for (final (index, id) in [29, 18, 10, 8].indexed) {
        final raw = _latestImport(id);
        final item = items[index];
        expect(item.importedAt, DateTime.parse(raw['date']! as String));
        expect(item.title, contains(_name(raw, 'book', 'title')));
        expect(item.title, contains(_name(raw, 'author', 'authorName')));
        expect(
          item.quality?.name,
          ((raw['quality']! as Map<String, Object?>)['quality']!
              as Map<String, Object?>)['name'],
        );
      }
    });
  });

  group('imported on a day', () {
    test('of the local day of a recorded import', () async {
      final harness = Harness();
      final raw = _latestImport(29);
      final day = DateTime.parse(raw['date']! as String).toLocal();

      final items = await ok(harness.calendar.importedOn(day));

      expect(harness.asked, [line(HttpMethod.get, 'history/since')]);
      final query = harness.server.requests.single.query;
      expect(query['eventType'], ['3']);
      expect(query['includeAuthor'], ['true']);
      expect(query['includeBook'], ['true']);
      // The other recorded imports are minutes away, and may fall on the day
      // before somewhere.
      expect(items.map((item) => item.itemRef), contains(bookRef(29)));
      expect(
        items.map((item) => item.itemRef).toSet(),
        hasLength(items.length),
      );
    });

    test('nothing of a day without imports', () async {
      expect(
        await ok(Harness().calendar.importedOn(DateTime(2020, 1, 1))),
        isEmpty,
      );
    });

    // The event of a whole download is not a second import.
    test('ignores events that are no import of a file', () async {
      final harness = Harness();
      final others = [
        {..._latestImport(29), 'eventType': 'downloadImported'},
      ];
      // Answered whatever was asked for.
      harness.server.overrides['history/since'] = FakeReadarr.body(
        jsonEncode(others),
      );
      final day = DateTime.parse(others.first['date']! as String).toLocal();

      expect(await ok(harness.calendar.importedOn(day)), isEmpty);
    });
  });
}
