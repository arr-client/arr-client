// Sonarr's mapping of its queue. Paging and the rest of the read are the shared
// Servarr client's. How the queue marks library items is in library_test.dart
// and episode_test.dart.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The recorded entries.
const _unmatched = 371094;
const _packFirst = 1759242772;
const _packSecond = 97818252;
const _upgrade = 368489279;
const _stalled = 1681750526;
const _delayed = 968557673;
const _completed = 1570342524;

Future<Map<int, QueueItem>> _queue(Harness harness) async => {
  for (final item in await ok(harness.queue.queue())) item.id: item,
};

/// The completed entry after [changes].
Future<QueueItem> _entryWith(Map<String, Object?> changes) async {
  final harness = Harness();
  byId(harness.server.queue, _completed).addAll(changes);
  return (await _queue(harness))[_completed]!;
}

void main() {
  test('the whole queue, unmatched downloads included', () async {
    final queue = await _queue(Harness());

    expect(
      queue.keys,
      unorderedEquals([
        _unmatched,
        _packFirst,
        _packSecond,
        _upgrade,
        _stalled,
        _delayed,
        _completed,
      ]),
    );
  });

  test('an entry names its episode and series', () async {
    final entry = (await _queue(Harness()))[_stalled]!;

    expect(entry.itemRef, episodeRef(16));
    expect(entry.parent, seriesRef(1));
  });

  test('an unmatched download names neither', () async {
    final entry = (await _queue(Harness()))[_unmatched]!;

    expect(entry.itemRef, isNull);
    expect(entry.parent, isNull);
  });

  test('a release of two episodes is two entries of one download', () async {
    final queue = await _queue(Harness());

    expect(queue[_packFirst]!.itemRef, episodeRef(18));
    expect(queue[_packSecond]!.itemRef, episodeRef(19));
    expect(queue[_packFirst]!.downloadId, queue[_packSecond]!.downloadId);
  });

  test('maps the fields of an entry', () async {
    final harness = Harness();
    final raw = byId(harness.server.queue, _upgrade);

    final entry = (await _queue(harness))[_upgrade]!;

    expect(entry.title, raw['title']);
    expect(entry.downloadId, raw['downloadId']);
    expect(entry.downloadClient, raw['downloadClient']);
    expect(entry.protocol, DownloadProtocol.torrent);
    expect(entry.quality?.id, 3);
    expect(entry.quality?.name, 'WEBDL-1080p');
    expect(entry.sizeLeft, 1468006400);
    expect(entry.progress, 0);
    expect(entry.eta, isNull);
    expect(entry.status, QueueStatus.warning);
    expect(entry.trackedState, TrackedState.downloading);
    expect(entry.messages, contains(raw['errorMessage']));
    expect(entry.needsManualImport, isFalse);
  });

  test('a completed download waiting for a manual import', () async {
    final harness = Harness();
    final raw = byId(harness.server.queue, _completed);
    final reason = (raw['statusMessages']! as List).single as Map;

    final entry = (await _queue(harness))[_completed]!;

    expect(entry.status, QueueStatus.completed);
    expect(entry.trackedState, TrackedState.importPending);
    expect(entry.severity, QueueSeverity.warning);
    expect(
      entry.messages,
      anyElement(contains((reason['messages'] as List).single)),
    );
    expect(entry.progress, 1);
    expect(entry.sizeLeft, 0);
    expect(entry.needsManualImport, isTrue);
  });

  test('a delayed release has no download yet', () async {
    final entry = (await _queue(Harness()))[_delayed]!;

    expect(entry.status, QueueStatus.delayed);
    expect(entry.trackedState, TrackedState.unknown);
    expect(entry.downloadId, isNull);
    expect(entry.downloadClient, isNull);
    expect(entry.eta?.inSeconds, 12 * 60 + 8);
  });

  test('time left of more than a day', () async {
    final entry = await _entryWith({'timeleft': '1.02:03:04'});

    expect(
      entry.eta,
      const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
    );
  });

  test('progress is the share downloaded', () async {
    expect((await _entryWith({'size': 1000, 'sizeleft': 250})).progress, 0.75);
    expect((await _entryWith({'size': 0, 'sizeleft': 0})).progress, 0);
  });

  for (final (name, status) in [
    ('queued', QueueStatus.queued),
    ('paused', QueueStatus.paused),
    ('downloading', QueueStatus.downloading),
    ('delay', QueueStatus.delayed),
    ('completed', QueueStatus.completed),
    ('warning', QueueStatus.warning),
    ('failed', QueueStatus.failed),
    ('downloadClientUnavailable', QueueStatus.downloadClientUnavailable),
    ('fallback', QueueStatus.fallback),
    ('unknown', QueueStatus.unknown),
    ('somethingNew', QueueStatus.unknown),
  ]) {
    test('status $name', () async {
      expect((await _entryWith({'status': name})).status, status);
    });
  }

  for (final (name, state) in [
    ('downloading', TrackedState.downloading),
    ('importPending', TrackedState.importPending),
    ('importBlocked', TrackedState.importBlocked),
    ('importing', TrackedState.importing),
    ('imported', TrackedState.imported),
    ('failedPending', TrackedState.failedPending),
    ('failed', TrackedState.failed),
    ('ignored', TrackedState.ignored),
    ('somethingNew', TrackedState.unknown),
  ]) {
    test('tracked state $name', () async {
      final entry = await _entryWith({'trackedDownloadState': name});

      expect(entry.trackedState, state);
    });
  }

  for (final (name, severity) in [
    ('ok', QueueSeverity.ok),
    ('warning', QueueSeverity.warning),
    ('error', QueueSeverity.error),
    ('somethingNew', QueueSeverity.unknown),
  ]) {
    test('tracked status $name', () async {
      final entry = await _entryWith({'trackedDownloadStatus': name});

      expect(entry.severity, severity);
    });
  }

  test('a blocked import needs a manual one', () async {
    final entry = await _entryWith({'trackedDownloadState': 'importBlocked'});

    expect(entry.needsManualImport, isTrue);
  });

  for (final (name, protocol) in [
    ('usenet', DownloadProtocol.usenet),
    ('somethingNew', DownloadProtocol.unknown),
  ]) {
    test('protocol $name', () async {
      expect((await _entryWith({'protocol': name})).protocol, protocol);
    });
  }

  test('an empty queue', () async {
    final harness = Harness();
    harness.server.queue.clear();

    expect(await ok(harness.queue.queue()), isEmpty);
  });

  test('a rejected key is a failure', () async {
    final harness = Harness();
    harness.server.always = FakeSonarr.body('', status: 401);

    expect(await failureOf(harness.queue.queue()), isA<AuthFailed>());
  });
}
