// History, events since, mark as failed and the blocklist (story 8, scenario 4,
// as story 4).
//
// Lidarr records a `trackFileImported` for each imported file and a
// `downloadImported` for the whole download. The first is the import event, so
// that one download is not reported twice; this does not say what the second
// maps to. History and queue records name an album; a blocklist record names a
// list of albums.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Map<String, Object?> _event(String type) =>
    pageRecords('activity_history')
        .firstWhere((record) => record['eventType'] == type);

Future<Map<int, HistoryEvent>> _history(
  Harness harness, {
  MediaTarget? target,
}) async => {
  for (final event in (await ok(harness.history.history(target: target))).items)
    event.id: event,
};

void main() {
  group('history', () {
    test('one page of everything, newest first', () async {
      final harness = Harness();

      final page = await ok(harness.history.history());

      final request = harness.server.requests.single;
      expect(request.path, 'api/v1/history');
      expect(request.query['page'], ['1']);
      expect(request.query['sortKey'], ['date']);
      expect(request.query['sortDirection'], ['descending']);
      expect(page.page, 1);
      expect(page.hasMore, isFalse);
      expect(page.items.map((event) => event.id), [
        for (final r in pageRecords('activity_history')) r['id'],
      ]);
    });

    for (final (word, type) in [
      ('grabbed', HistoryEventType.grabbed),
      ('trackFileImported', HistoryEventType.imported),
      ('downloadFailed', HistoryEventType.failed),
      ('trackFileDeleted', HistoryEventType.deleted),
      ('albumImportIncomplete', HistoryEventType.other),
    ]) {
      test('$word is ${type.name}', () async {
        final raw = _event(word);

        final event = (await _history(Harness()))[raw['id']]!;

        expect(event.eventType, type);
        expect(event.itemRef, albumRef(raw['albumId']! as int));
        expect(event.date, DateTime.parse(raw['date']! as String));
        expect(event.sourceTitle, raw['sourceTitle']);
        expect(event.downloadId, raw['downloadId']);
      });
    }

    test('trackFileRenamed is renamed', () async {
      final harness = Harness();
      final raw = harness.server.history.first
        ..['eventType'] = 'trackFileRenamed';

      final event = (await _history(harness))[raw['id']]!;

      expect(event.eventType, HistoryEventType.renamed);
    });

    test('keeps no address of an indexer', () async {
      final harness = Harness();
      final id = _event('grabbed')['id']! as int;
      byId(harness.server.history, id)['data'] = {
        'indexer': 'Example',
        'downloadUrl': 'https://indexer.example/get?apikey=SECRET',
        'nzbInfoUrl': 'https://indexer.example/info/1',
      };

      final event = (await _history(harness))[id]!;

      expect(event.details, {'indexer': 'Example'});
    });

    test('of an album', () async {
      final harness = Harness();

      final events = await _history(harness, target: album(2));

      final request = harness.server.requests.single;
      expect(request.path, 'api/v1/history');
      expect(request.query['albumId'], ['2']);
      expect(events.keys, [
        for (final r in pageRecords('activity_history'))
          if (r['albumId'] == 2) r['id'],
      ]);
    });

    test('of an artist, whole, as the first page', () async {
      final harness = Harness();

      final page = await ok(harness.history.history(target: artist()));
      final next = await ok(harness.history.history(target: artist(), page: 2));

      expect(harness.asked, [line(HttpMethod.get, 'history/artist')]);
      expect(harness.server.requests.single.query, {
        'artistId': ['1'],
      });
      expect(page.items, hasLength(harness.server.history.length));
      expect(page.hasMore, isFalse);
      expect(next.items, isEmpty);
    });

    test('is of artists and albums only', () async {
      final harness = Harness();

      await expectProgrammingError(
        () => harness.history.history(target: movie),
      );

      expect(harness.server.requests, isEmpty);
    });
  });

  test('marks a grab as failed', () async {
    final harness = Harness();
    final id = _event('grabbed')['id']! as int;

    await ok(harness.history.markFailed(id));

    expect(harness.asked, [line(HttpMethod.post, 'history/failed/$id')]);
  });

  for (final MapEntry(key: cause, value: (answer, expected))
      in writeFailures.entries) {
    test('$cause is reported and marking is sent once', () async {
      final harness = Harness()..server.writeAnswer = answer;

      final failure = await failureOf(harness.history.markFailed(1));

      expect(failure.runtimeType, expected);
      expect(harness.server.requests, hasLength(1));
    });
  }

  group('events since', () {
    test('asks since the server time given, newest first', () async {
      final harness = Harness();
      final since = DateTime.parse(_event('downloadFailed')['date']! as String);

      final events = await ok(harness.history.eventsSince(since));

      expect(harness.asked, [line(HttpMethod.get, 'history/since')]);
      final query = harness.server.requests.single.query;
      expect(DateTime.parse(query['date']!.single), since);
      // Every kind: failures are notified too.
      expect(query.containsKey('eventType'), isFalse);
      final expected = records('activity_history_since')
          .where((r) => !DateTime.parse(r['date']! as String).isBefore(since))
          .map((r) => r['id']);
      expect(events.map((event) => event.id), unorderedEquals(expected));
      for (var i = 1; i < events.length; i++) {
        expect(events[i].date.isAfter(events[i - 1].date), isFalse);
      }
      expect(
        events.map((event) => event.eventType),
        containsAll([HistoryEventType.failed, HistoryEventType.grabbed]),
      );
    });
  });

  group('blocklist', () {
    test('one page, newest first', () async {
      final harness = Harness();
      final raw = pageRecords('activity_blocklist').single;

      final page = await ok(harness.history.blocklist());

      final request = harness.server.requests.single;
      expect(request.path, 'api/v1/blocklist');
      expect(request.query['page'], ['1']);
      expect(request.query['sortKey'], ['date']);
      expect(request.query['sortDirection'], ['descending']);
      expect(page.hasMore, isFalse);
      final entry = page.items.single;
      expect(entry.id, raw['id']);
      expect(entry.sourceTitle, raw['sourceTitle']);
      expect(entry.date, DateTime.parse(raw['date']! as String));
      expect(entry.quality?.name, 'FLAC');
      expect(entry.reason, raw['message']);
      expect(entry.itemRef, albumRef(1));
    });

    test('an entry of several albums names the artist', () async {
      final harness = Harness();
      harness.server.blocklist.single['albumIds'] = [1, 2];

      final entry = (await ok(harness.history.blocklist())).items.single;

      expect(entry.itemRef, artistRef(1));
    });

    test('removes one entry', () async {
      final harness = Harness();

      await ok(harness.history.unblock([3]));

      expect(harness.asked, [line(HttpMethod.delete, 'blocklist/3')]);
    });

    test('removes several entries at once', () async {
      final harness = Harness();

      await ok(harness.history.unblock([3, 4]));

      expect(harness.asked, [line(HttpMethod.delete, 'blocklist/bulk')]);
      expect(sentBody(harness.server.writes.single), {
        'ids': [3, 4],
      });
    });

    test('of no entries sends nothing', () async {
      final harness = Harness();

      await ok(harness.history.unblock([]));

      expect(harness.server.requests, isEmpty);
    });
  });
}
