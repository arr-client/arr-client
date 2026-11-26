// The overall history, the events since a time, marking a grab as failed and
// the blocklist. The history of one item is in item_history_test.dart.
//
// A history event names its episode. A blocklist entry names its series: it
// has `seriesId` and `episodeIds` but no `episodeId`.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_support.dart';
import 'support.dart';

// The recorded events, newest first.
const _ids = [43, 42, 41, 8, 7, 6, 5, 4, 3, 2, 1];

/// Enough copies of the recorded events to need more than one page.
void _fill(ActivityServer server) {
  final recorded = [...server.events];
  for (var round = 1; round < 6; round++) {
    server.events.addAll([
      for (final event in recorded)
        {...event, 'id': (event['id']! as int) + round * 100},
    ]);
  }
}

void main() {
  group('overall history', () {
    test('asks for a page, newest first, of every item', () async {
      final harness = ActivityHarness();

      await ok(harness.history.history());

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/history');
      expect(request.query['page'], ['1']);
      expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
      expect(request.query['sortKey'], ['date']);
      expect(request.query['sortDirection'], ['descending']);
      expect(request.query, isNot(contains('episodeId')));
      expect(request.query, isNot(contains('seriesIds')));
    });

    test('maps the events', () async {
      final harness = ActivityHarness();

      final page = await ok(harness.history.history());

      expect(page.items.map((event) => event.id), _ids);
      expect(page.page, 1);
      expect(page.hasMore, isFalse);
      final byId = {for (final event in page.items) event.id: event};
      expect(byId[43]!.eventType, HistoryEventType.imported);
      expect(byId[43]!.itemRef, episodeRef(21));
      expect(byId[43]!.date, DateTime.utc(2026, 11, 26, 15, 13, 56));
      expect(byId[43]!.downloadId, pairDownload);
      expect(byId[42]!.eventType, HistoryEventType.failed);
      expect(byId[42]!.itemRef, episodeRef(49));
      expect(byId[1]!.eventType, HistoryEventType.grabbed);
      expect(byId[1]!.itemRef, episodeRef(19));
    });

    // A grab records the indexer's addresses, which may carry its key.
    test('keeps no address of a grab', () async {
      final harness = ActivityHarness();
      final data =
          byId(harness.activity.events, 1)['data']! as Map<String, Object?>;
      expect(data.keys, containsAll(['downloadUrl', 'guid', 'nzbInfoUrl']));

      final page = await ok(harness.history.history());

      final event = page.items.singleWhere((event) => event.id == 1);
      expect(event.details, containsPair('size', data['size']));
      for (final name in ['downloadUrl', 'guid', 'nzbInfoUrl']) {
        expect(event.details, isNot(contains(name)));
      }
    });

    test('reads one page at a time', () async {
      final harness = ActivityHarness();
      _fill(harness.activity);
      final total = harness.activity.events.length;

      final first = await ok(harness.history.history());
      final second = await ok(harness.history.history(page: 2));

      expect(harness.activity.requests, hasLength(2));
      expect(harness.activity.requests.last.query['page'], ['2']);
      expect(first.hasMore, isTrue);
      expect(second.page, 2);
      expect(second.hasMore, isFalse);
      expect(first.items.length + second.items.length, total);
    });

    test('a rejected key is a failure', () async {
      final harness = ActivityHarness()
        ..activity.always = FakeSonarr.body('', status: 401);

      expect(await failureOf(harness.history.history()), isA<AuthFailed>());
    });
  });

  group('events since a time', () {
    final since = DateTime.utc(2026, 11, 26, 15, 10, 28);

    test('asks for them with the time in UTC', () async {
      final harness = ActivityHarness();

      await ok(harness.history.eventsSince(since.toLocal()));

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/history/since');
      final date = request.query['date']!.single;
      expect(date, endsWith('Z'));
      expect(DateTime.parse(date), since);
    });

    test('gives them newest first, each with its episode', () async {
      final harness = ActivityHarness();

      final events = await ok(harness.history.eventsSince(since));

      expect(events.map((event) => event.id), [43, 42, 41, 8, 7, 6, 5, 4, 3]);
      expect(events.first.itemRef, episodeRef(21));
      expect(events.first.eventType, HistoryEventType.imported);
    });

    test('none', () async {
      final harness = ActivityHarness();
      harness.activity.eventsAfter.clear();

      expect(await ok(harness.history.eventsSince(since)), isEmpty);
    });
  });

  group('mark as failed', () {
    test('marks the event', () async {
      final harness = ActivityHarness();

      await ok(harness.history.markFailed(4));

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.post);
      expect(request.path, 'api/v3/history/failed/4');
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });

    test('an unknown outcome is reported and not retried', () async {
      final harness = ActivityHarness()
        ..activity.writeAnswer = FakeSonarr.body('', status: 504, write: true);

      expect(
        await failureOf(harness.history.markFailed(4)),
        isA<OutcomeUnknown>(),
      );
      expect(harness.activity.requests, hasLength(1));
    });
  });

  group('blocklist', () {
    test('asks for a page, newest first', () async {
      final harness = ActivityHarness();

      await ok(harness.history.blocklist());

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/blocklist');
      expect(request.query['page'], ['1']);
      expect(request.query['sortKey'], ['date']);
      expect(request.query['sortDirection'], ['descending']);
    });

    test('an entry names its series', () async {
      final harness = ActivityHarness();
      final raw = harness.activity.blocked.single;
      expect(raw, isNot(contains('episodeId')));
      expect(raw['episodeIds'], hasLength(2));

      final page = await ok(harness.history.blocklist());

      final entry = page.items.single;
      expect(entry.id, 1);
      expect(entry.itemRef, seriesRef(1));
      expect(entry.sourceTitle, raw['sourceTitle']);
      expect(entry.date, DateTime.utc(2026, 11, 26, 15, 13, 45));
      expect(entry.quality?.id, 3);
      expect(entry.quality?.name, 'WEBDL-1080p');
      expect(entry.reason, raw['message']);
      expect(page.hasMore, isFalse);
    });

    test('an empty one', () async {
      final harness = ActivityHarness();
      harness.activity.blocked.clear();

      final page = await ok(harness.history.blocklist());

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('removes one entry', () async {
      final harness = ActivityHarness();

      await ok(harness.history.unblock([1]));

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.delete);
      expect(request.path, 'api/v3/blocklist/1');
      expect(request.body, isNull);
    });

    test('removes several entries', () async {
      final harness = ActivityHarness();

      await ok(harness.history.unblock([1, 2]));

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.delete);
      expect(request.path, 'api/v3/blocklist/bulk');
      expect(sentBody(request), {
        'ids': [1, 2],
      });
    });

    test('removing nothing asks nothing', () async {
      final harness = ActivityHarness();

      await ok(harness.history.unblock(const []));

      expect(harness.activity.requests, isEmpty);
    });
  });
}
