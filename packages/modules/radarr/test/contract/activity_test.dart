// The queue actions, the history and the blocklist against recorded answers
// (spec story 4). Paging and mapping the records is shared Servarr behaviour and
// is tested there; here is what Radarr binds.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_support.dart';
import 'library_support.dart';

/// Every write that is not a manual import.
final _writes = <String, ServiceResult<void> Function(Activity)>{
  'remove': (activity) => activity.queue.remove(
    7,
    const RemoveOptions(removeFromClient: true, blocklist: false),
  ),
  'removeMany': (activity) => activity.queue.removeMany(const [
    7,
    8,
  ], const RemoveOptions(removeFromClient: true, blocklist: false)),
  'grabNow': (activity) => activity.queue.grabNow(7),
  'markFailed': (activity) => activity.history.markFailed(5),
  'unblock one': (activity) => activity.history.unblock(const [2]),
  'unblock several': (activity) => activity.history.unblock(const [2, 1]),
};

/// The one request of [activity], which must be a [method] of [path].
ServiceRequest _only(Activity activity, HttpMethod method, String path) {
  final request = activity.server.requests.single;
  expect(request.method, method);
  expect(request.path, 'api/v3/$path');
  return request;
}

void main() {
  group('queue', () {
    test('says which downloads wait for a manual import', () async {
      final items = await succeed(Activity().queue.queue());

      expect(
        {
          for (final item in items)
            if (item.needsManualImport) (item.itemRef, item.downloadId),
        },
        {(movieRef(1), matchedDownload), (null, unmatchedDownload)},
      );
      expect(
        items.singleWhere((item) => item.status == QueueStatus.delayed).itemRef,
        movieRef(6),
      );
    });

    for (final (name, options, query) in const [
      (
        'removes from the download client',
        RemoveOptions(removeFromClient: true, blocklist: false),
        {
          'removeFromClient': ['true'],
          'blocklist': ['false'],
        },
      ),
      (
        'leaves the download in the client',
        // `searchReplacement` only matters with a blocklist.
        RemoveOptions(
          removeFromClient: false,
          blocklist: false,
          searchReplacement: true,
        ),
        {
          'removeFromClient': ['false'],
          'blocklist': ['false'],
        },
      ),
      (
        'blocks the release without a replacement search',
        RemoveOptions(removeFromClient: true, blocklist: true),
        {
          'removeFromClient': ['true'],
          'blocklist': ['true'],
          'skipRedownload': ['true'],
        },
      ),
      (
        'blocks the release and searches for a replacement',
        RemoveOptions(
          removeFromClient: true,
          blocklist: true,
          searchReplacement: true,
        ),
        {
          'removeFromClient': ['true'],
          'blocklist': ['true'],
          'skipRedownload': ['false'],
        },
      ),
    ]) {
      test('$name, for one entry', () async {
        final activity = Activity();

        await succeed(activity.queue.remove(7, options));

        final request = _only(activity, HttpMethod.delete, 'queue/7');
        expect(request.query, query);
        expect(request.body, isNull);
      });

      test('$name, for several entries', () async {
        final activity = Activity();

        await succeed(activity.queue.removeMany(const [7, 8], options));

        final request = _only(activity, HttpMethod.delete, 'queue/bulk');
        expect(request.query, query);
        expect(sent(request), {
          'ids': [7, 8],
        });
      });
    }

    test('removes nothing for no entries', () async {
      final activity = Activity();

      await succeed(
        activity.queue.removeMany(
          const [],
          const RemoveOptions(removeFromClient: true, blocklist: false),
        ),
      );

      expect(activity.server.requests, isEmpty);
    });

    test('grabs a delayed entry at once', () async {
      final activity = Activity();

      await succeed(activity.queue.grabNow(7));

      final request = _only(activity, HttpMethod.post, 'queue/grab/7');
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });
  });

  group('history', () {
    test('asks for the newest events first', () async {
      final activity = Activity();

      await succeed(activity.history.history());

      final request = _only(activity, HttpMethod.get, 'history');
      expect(request.query['page'], ['1']);
      expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
      expect(request.query['sortKey'], ['date']);
      expect(request.query['sortDirection'], ['descending']);
    });

    test('maps the events of every movie', () async {
      final wire = pageRecords('history_activity');

      final page = await succeed(Activity().history.history());

      expect(page.page, 1);
      expect(page.hasMore, isFalse);
      expect(
        page.items.map((event) => event.id),
        wire.map((record) => record['id']),
      );
      expect(page.items.map((event) => event.itemRef), [
        for (final record in wire) movieRef(record['movieId']! as int),
      ]);
      expect(
        page.items.map((event) => event.downloadId),
        wire.map((record) => record['downloadId']),
      );
      expect(page.items.map((event) => event.eventType), [
        for (final record in wire)
          switch (record['eventType']) {
            'grabbed' => HistoryEventType.grabbed,
            'downloadFolderImported' => HistoryEventType.imported,
            'downloadFailed' => HistoryEventType.failed,
            final other => fail('Unexpected recording: $other'),
          },
      ]);
      for (final event in page.items) {
        expect(event.details.keys, isNot(contains('downloadUrl')));
        expect(event.details.keys, isNot(contains('guid')));
      }
    });

    test('asks for a later page and says that more follow', () async {
      final activity = Activity();
      activity.server.answers['api/v3/history'] = jsonAnswer({
        ...fixture('history_activity')! as Map<String, Object?>,
        'page': 2,
        'pageSize': 10,
        'totalRecords': 21,
      });

      final page = await succeed(activity.history.history(page: 2));

      expect(activity.server.requests.single.query['page'], ['2']);
      expect(page.page, 2);
      expect(page.hasMore, isTrue);
    });

    test('marks a grab as failed', () async {
      final activity = Activity();

      await succeed(activity.history.markFailed(5));

      final request = _only(activity, HttpMethod.post, 'history/failed/5');
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });

    test('asks for the events since a time, in UTC', () async {
      final activity = Activity();
      final since = DateTime.utc(2026, 11, 26, 14, 30, 5);

      await succeed(activity.history.eventsSince(since.toLocal()));

      final request = _only(activity, HttpMethod.get, 'history/since');
      expect(request.query['date']!.single, endsWith('Z'));
      expect(DateTime.parse(request.query['date']!.single), since);
    });

    test('gives the events since then newest first', () async {
      // Radarr sends them oldest first.
      final wire = records(fixture('history_since'));

      final events = await succeed(
        Activity().history.eventsSince(DateTime.utc(2026)),
      );

      expect(
        events.map((event) => event.id),
        wire.map((record) => record['id']).toList().reversed,
      );
      expect(events.map((event) => event.itemRef), [
        for (final record in wire.reversed) movieRef(record['movieId']! as int),
      ]);
    });
  });

  group('blocklist', () {
    test('asks for the newest entries first', () async {
      final activity = Activity();

      await succeed(activity.history.blocklist());

      final request = _only(activity, HttpMethod.get, 'blocklist');
      expect(request.query['page'], ['1']);
      expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
      expect(request.query['sortKey'], ['date']);
      expect(request.query['sortDirection'], ['descending']);
    });

    test('maps the blocked releases and why they were blocked', () async {
      final wire = pageRecords('blocklist');

      final page = await succeed(Activity().history.blocklist());

      expect(page.page, 1);
      expect(page.hasMore, isFalse);
      expect(page.items, hasLength(2));
      for (final (index, entry) in page.items.indexed) {
        final record = wire[index];
        expect(entry.id, record['id']);
        expect(entry.itemRef, movieRef(record['movieId']! as int));
        expect(entry.sourceTitle, record['sourceTitle']);
        expect(entry.date, DateTime.parse(record['date']! as String));
        expect(entry.quality?.id, 7);
        expect(entry.quality?.name, 'Bluray-1080p');
        expect(entry.reason, record['message']);
      }
    });

    test('asks for a later page', () async {
      final activity = Activity();

      final page = await succeed(activity.history.blocklist(page: 3));

      expect(activity.server.requests.single.query['page'], ['3']);
      expect(page.page, 3);
    });

    test('removes one entry', () async {
      final activity = Activity();

      await succeed(activity.history.unblock(const [2]));

      final request = _only(activity, HttpMethod.delete, 'blocklist/2');
      expect(request.body, isNull);
    });

    test('removes several entries at once', () async {
      final activity = Activity();

      await succeed(activity.history.unblock(const [2, 1]));

      final request = _only(activity, HttpMethod.delete, 'blocklist/bulk');
      expect(sent(request), {
        'ids': [2, 1],
      });
    });

    test('removes nothing for no entries', () async {
      final activity = Activity();

      await succeed(activity.history.unblock(const []));

      expect(activity.server.requests, isEmpty);
    });
  });

  group('failures', () {
    for (final MapEntry(key: name, value: write) in _writes.entries) {
      test('$name is sent once and its failure passed on', () async {
        const failure = OutcomeUnknown();
        final activity = Activity()..server.down = failedAnswer(failure);

        expect(await failureOf(write(activity)), same(failure));
        expect(activity.server.requests, hasLength(1));
      });
    }

    for (final MapEntry(key: name, value: read)
        in <String, ServiceResult<Object?> Function(Activity)>{
          'history': (activity) => activity.history.history(),
          'eventsSince': (activity) =>
              activity.history.eventsSince(DateTime.utc(2026)),
          'blocklist': (activity) => activity.history.blocklist(),
          'importCandidates': (activity) =>
              activity.queue.importCandidates(waiting('ABCDEF01')),
          'importChoices': (activity) => activity.queue.importChoices(),
        }.entries) {
      test('$name passes on a failure', () async {
        const failure = AuthFailed();
        final activity = Activity()..server.down = failedAnswer(failure);

        expect(await failureOf(read(activity)), same(failure));
      });
    }
  });
}
