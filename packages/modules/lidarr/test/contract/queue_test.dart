// The download queue and its actions (story 8, scenario 4, as story 4).
//
// Lidarr names a protocol by its class, as `TorrentDownloadProtocol`, and has a
// tracked state of its own, `importFailed`, for a download it could not import.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The recorded record whose tracked state or artist is as [test] says.
Map<String, Object?> _recorded(bool Function(Map<String, Object?>) test) =>
    pageRecords('activity_queue').singleWhere(test);

Map<String, Object?> _failedImport() =>
    _recorded((r) => r['trackedDownloadState'] == 'importFailed');

Map<String, Object?> _unmatched() => _recorded((r) => r['artistId'] == null);

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
    expect(request.query['includeUnknownArtistItems'], ['true']);
  });

  test('names the album and its artist', () async {
    final raw = _failedImport();

    final item = (await _queue(Harness()))[raw['id']]!;

    expect(item.itemRef, albumRef(raw['albumId']! as int));
    expect(item.parent, artistRef(raw['artistId']! as int));
    expect(item.title, raw['title']);
    expect(item.downloadId, raw['downloadId']);
    expect(item.quality?.name, 'MP3-320');
    expect(item.protocol, DownloadProtocol.torrent);
  });

  test('a download no artist matches names nothing', () async {
    final raw = _unmatched();

    final item = (await _queue(Harness()))[raw['id']]!;

    expect(item.itemRef, isNull);
    expect(item.parent, isNull);
    expect(item.needsManualImport, isFalse);
  });

  test('a download that could not be imported awaits help', () async {
    final raw = _failedImport();

    final item = (await _queue(Harness()))[raw['id']]!;

    expect(item.status, QueueStatus.completed);
    expect(item.severity, QueueSeverity.warning);
    expect(item.trackedState, TrackedState.importBlocked);
    expect(item.needsManualImport, isTrue);
    expect(item.messages, isNotEmpty);
    expect(item.progress, 1);
  });

  test('a Usenet download', () async {
    final harness = Harness();
    final id = _unmatched()['id']! as int;
    byId(harness.server.queue, id)['protocol'] = 'UsenetDownloadProtocol';

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
