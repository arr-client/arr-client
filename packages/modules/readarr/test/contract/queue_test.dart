// The download queue and its actions (story 8, scenario 4, as story 4).
//
// Readarr has a tracked state of its own, `importFailed`, for a download it
// could not import.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Map<String, Object?> _recorded(String trackedState) => pageRecords(
  'activity_queue',
).singleWhere((record) => record['trackedDownloadState'] == trackedState);

Future<Map<int, QueueItem>> _queue(Harness harness) async => {
  for (final item in await ok(harness.queue.queue())) item.id: item,
};

const _removal = RemoveOptions(removeFromClient: true, blocklist: false);

void main() {
  test('the whole queue, unmatched downloads included', () async {
    final harness = Harness();

    final items = await _queue(harness);

    expect(
      items.keys,
      unorderedEquals([for (final r in pageRecords('activity_queue')) r['id']]),
    );
    final request = harness.server.requests.single;
    expect(request.path, 'api/v1/queue');
    expect(request.query['includeUnknownAuthorItems'], ['true']);
  });

  test('names the book and its author', () async {
    final raw = _recorded('downloading');

    final item = (await _queue(Harness()))[raw['id']]!;

    expect(item.itemRef, bookRef(19));
    expect(item.parent, authorRef(1));
    expect(item.title, raw['title']);
    expect(item.downloadId, raw['downloadId']);
    expect(item.quality?.name, 'EPUB');
    expect(item.protocol, DownloadProtocol.torrent);
    expect(item.status, QueueStatus.warning);
    expect(item.progress, 0);
    expect(item.needsManualImport, isFalse);
  });

  test('a download that could not be imported awaits help', () async {
    final raw = _recorded('importFailed');

    final item = (await _queue(Harness()))[raw['id']]!;

    expect(item.status, QueueStatus.completed);
    expect(item.severity, QueueSeverity.warning);
    expect(item.trackedState, TrackedState.importBlocked);
    expect(item.needsManualImport, isTrue);
    expect(item.messages, isNotEmpty);
    expect(item.progress, 1);
    // No author matches it.
    expect(item.itemRef, isNull);
    expect(item.parent, isNull);
  });

  test('a Usenet download', () async {
    final harness = Harness();
    final id = _recorded('downloading')['id']! as int;
    byId(harness.server.queue, id)['protocol'] = 'usenet';

    expect((await _queue(harness))[id]!.protocol, DownloadProtocol.usenet);
  });

  group('actions', () {
    test('removes one entry, stating what happens to it', () async {
      final harness = Harness();

      await ok(harness.queue.remove(7, _removal));

      final write = harness.server.writes.single;
      expect(write.method, HttpMethod.delete);
      expect(write.path, 'api/v1/queue/7');
      expect(write.query, {
        'removeFromClient': ['true'],
        'blocklist': ['false'],
      });
    });

    test('removes and blocklists, searching for a replacement', () async {
      final harness = Harness();

      await ok(
        harness.queue.remove(
          7,
          const RemoveOptions(
            removeFromClient: false,
            blocklist: true,
            searchReplacement: true,
          ),
        ),
      );

      expect(harness.server.writes.single.query, {
        'removeFromClient': ['false'],
        'blocklist': ['true'],
        'skipRedownload': ['false'],
      });
    });

    test('removes several entries at once', () async {
      final harness = Harness();

      await ok(harness.queue.removeMany([7, 9], _removal));

      final write = harness.server.writes.single;
      expect(write.method, HttpMethod.delete);
      expect(write.path, 'api/v1/queue/bulk');
      expect(sentBody(write), {
        'ids': [7, 9],
      });
    });

    test('grabs a delayed entry now', () async {
      final harness = Harness();

      await ok(harness.queue.grabNow(7));

      expect(harness.asked, [line(HttpMethod.post, 'queue/grab/7')]);
    });

    for (final MapEntry(key: cause, value: (answer, expected))
        in writeFailures.entries) {
      test('$cause is reported and a removal is sent once', () async {
        final harness = Harness()..server.writeAnswer = answer;

        final failure = await failureOf(harness.queue.remove(7, _removal));

        expect(failure.runtimeType, expected);
        expect(harness.server.requests, hasLength(1));
      });
    }
  });
}
