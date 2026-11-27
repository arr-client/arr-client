// History, events since, mark as failed and the blocklist (story 8, scenario 4,
// as story 4).
//
// Readarr records a `bookFileImported` for each imported file and a
// `downloadImported` for the whole download. The first is the import event, so
// that one download is not reported twice; this does not say what the second
// maps to beyond that. History and queue records name a book; a blocklist
// record names a list of books.

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
      ('bookFileImported', HistoryEventType.imported),
      ('downloadFailed', HistoryEventType.failed),
    ]) {
      test('$word is ${type.name}', () async {
        final raw = _event(word);

        final event = (await _history(Harness()))[raw['id']]!;

        expect(event.eventType, type);
        expect(event.itemRef, bookRef(raw['bookId']! as int));
        expect(event.date, DateTime.parse(raw['date']! as String));
        expect(event.sourceTitle, raw['sourceTitle']);
        expect(event.downloadId, raw['downloadId']);
      });
    }

    for (final (word, type) in [
      ('bookFileDeleted', HistoryEventType.deleted),
      ('bookFileRenamed', HistoryEventType.renamed),
      ('bookImportIncomplete', HistoryEventType.other),
    ]) {
      test('$word is ${type.name}', () async {
        final harness = Harness();
        final raw = harness.server.history.first..['eventType'] = word;

        final event = (await _history(harness))[raw['id']]!;

        expect(event.eventType, type);
      });
    }

    test('a whole download is not a second import', () async {
      final harness = Harness();
      final raw = harness.server.history.first
        ..['eventType'] = 'downloadImported';

      final event = (await _history(harness))[raw['id']]!;

      expect(event.eventType, isNot(HistoryEventType.imported));
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

    test('of a book', () async {
      final harness = Harness();

      final events = await _history(harness, target: book(19));

      final request = harness.server.requests.single;
      expect(request.path, 'api/v1/history');
      expect(request.query['bookId'], ['19']);
      expect(events.keys, [
        for (final r in pageRecords('activity_history'))
          if (r['bookId'] == 19) r['id'],
      ]);
    });

    test('of an author, whole, as the first page', () async {
      final harness = Harness();

      final page = await ok(harness.history.history(target: author()));
      final next = await ok(harness.history.history(target: author(), page: 2));

      expect(harness.asked, [line(HttpMethod.get, 'history/author')]);
      expect(harness.server.requests.single.query, {
        'authorId': ['1'],
      });
      expect(page.items, hasLength(harness.server.history.length));
      expect(page.hasMore, isFalse);
      expect(next.items, isEmpty);
    });

    test('is of authors and books only', () async {
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
        containsAll([HistoryEventType.failed, HistoryEventType.imported]),
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
      expect(entry.quality?.name, 'EPUB');
      expect(entry.reason, raw['message']);
      expect(entry.itemRef, bookRef(19));
    });

    test('an entry of several books names the author', () async {
      final harness = Harness();
      harness.server.blocklist.single['bookIds'] = [8, 19];

      final entry = (await ok(harness.history.blocklist())).items.single;

      expect(entry.itemRef, authorRef(1));
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
