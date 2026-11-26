// The calendar of album releases, and what was imported (story 8, scenario 4,
// as story 6).
//
// Lidarr's import event is `trackFileImported`, number 3 of its
// `EntityHistoryEventType`: one for each file, listed here by album. The shared
// calendar takes the event the other services have by default.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _from = DateTime.utc(1994);
final _to = DateTime.utc(2009);

Future<Map<ItemRef, CalendarEvent>> _events(Harness harness) async => {
  for (final event in await ok(harness.calendar.events(_from, _to)))
    event.itemRef: event,
};

/// The latest recorded import of [album].
Map<String, Object?> _latestImport(int album) =>
    pageRecords('overview_history_imports')
        .firstWhere((record) => record['albumId'] == album);

void main() {
  group('events', () {
    test('the monitored albums released in the range, by date', () async {
      final harness = Harness();

      final events = await ok(harness.calendar.events(_from, _to));

      expect(events.map((event) => event.itemRef), [
        albumRef(2),
        albumRef(1),
        albumRef(3),
      ]);
      final request = harness.server.requests.singleWhere(
        (request) => request.path == 'api/v1/calendar',
      );
      expect(request.query['includeArtist'], ['true']);
      expect(request.query['unmonitored'], anyOf(isNull, ['false']));
      expect(
        DateTime.parse(request.query['start']!.single).isBefore(_to),
        true,
      );
      expect(DateTime.parse(request.query['end']!.single).isAfter(_from), true);
    });

    test('maps a release with its artist', () async {
      final harness = Harness();
      final raw = byId(records('overview_calendar'), 2);
      final artist = raw['artist']! as Map<String, Object?>;

      final event = (await _events(harness))[albumRef(2)]!;

      expect(event.date, DateTime.parse(raw['releaseDate']! as String));
      expect(event.dateKind, CalendarDateKind.releaseDate);
      expect(event.title, contains(raw['title']! as String));
      expect(event.title, contains(artist['artistName']! as String));
    });

    test('keeps only the releases of the range', () async {
      final events = await ok(
        Harness().calendar.events(
          DateTime.utc(1997, 9, 29),
          DateTime.utc(2008, 4, 8),
        ),
      );

      expect(events.map((event) => event.itemRef), [albumRef(1)]);
    });

    test('states follow the statistics and the queue', () async {
      final queued = await _events(Harness());
      final idle = await _events(Harness()..server.queue.clear());

      expect(queued[albumRef(1)]!.state, ItemState.downloading);
      expect(queued[albumRef(2)]!.state, ItemState.downloaded);
      expect(idle[albumRef(1)]!.state, ItemState.partial);
      expect(idle[albumRef(3)]!.state, ItemState.missing);
    });

    test('fail when the queue cannot be read', () async {
      final harness = Harness();
      harness.server.overrides['queue'] = FakeLidarr.body('', status: 500);

      expect(
        await failureOf(harness.calendar.events(_from, _to)),
        isA<ServerError>(),
      );
    });

    test('skip an album without a release date', () async {
      final harness = Harness();
      byId(harness.server.calendar, 2).remove('releaseDate');

      expect((await _events(harness)).keys, isNot(contains(albumRef(2))));
    });
  });

  group('recently added', () {
    test('asks for imports with their artist and album', () async {
      final harness = Harness();

      await ok(harness.calendar.recentlyAdded());

      expect(harness.asked, [line(HttpMethod.get, 'history')]);
      final query = harness.server.requests.single.query;
      expect(query['eventType'], ['3']);
      expect(query['includeArtist'], ['true']);
      expect(query['includeAlbum'], ['true']);
      expect(query['sortDirection'], ['descending']);
    });

    test('each album once, with its latest import', () async {
      final items = await ok(Harness().calendar.recentlyAdded());

      expect(items.map((item) => item.itemRef), [albumRef(1), albumRef(2)]);
      for (final (index, id) in [1, 2].indexed) {
        final raw = _latestImport(id);
        final item = items[index];
        expect(item.importedAt, DateTime.parse(raw['date']! as String));
        expect(
          item.title,
          contains((raw['album']! as Map<String, Object?>)['title']! as String),
        );
        expect(
          item.title,
          contains(
            (raw['artist']! as Map<String, Object?>)['artistName']! as String,
          ),
        );
        expect(
          item.quality?.name,
          ((raw['quality']! as Map<String, Object?>)['quality']!
              as Map<String, Object?>)['name'],
        );
      }
    });
  });

  group('imported on a day', () {
    test('of the local day of the recorded imports', () async {
      final harness = Harness();
      final raw = _latestImport(2);
      final day = DateTime.parse(raw['date']! as String).toLocal();

      final items = await ok(harness.calendar.importedOn(day));

      expect(harness.asked, [line(HttpMethod.get, 'history/since')]);
      final query = harness.server.requests.single.query;
      expect(query['eventType'], ['3']);
      expect(query['includeArtist'], ['true']);
      expect(query['includeAlbum'], ['true']);
      // The other recorded imports are minutes away, and may fall on the next
      // day somewhere.
      expect(items.map((item) => item.itemRef), contains(albumRef(2)));
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
      final others = harness.server.historySince
          .where((record) => record['eventType'] == 'downloadImported')
          .toList();
      // Answered whatever was asked for.
      harness.server.overrides['history/since'] = FakeLidarr.body(
        jsonEncode(others),
      );
      final day = DateTime.parse(others.first['date']! as String).toLocal();

      expect(await ok(harness.calendar.importedOn(day)), isEmpty);
    });
  });
}
