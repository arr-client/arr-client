// Matching a queue entry to a download client's torrent: data-model.md
// DownloadProgress, spec story 7.
//
// API for T109, in lib/src/progress/match_progress.dart and exported by
// core.dart:
//
//   DownloadProgress? matchProgress(
//     QueueItem item,
//     Iterable<DownloadProgress> torrents,
//   );
//
// `torrents` holds what every qBittorrent instance of the active profile
// reported, one instance after another in instance order. The caller chooses the
// instances, orders them and leaves out those that gave no answer.
//
// Returns the first of `torrents` whose `hash` or `infohashV1` equals
// `item.downloadId` ignoring case: the record itself, with its figures as they
// are. Returns null when none does, and when `downloadId` is null or empty.
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

const _hash = '0123456789abcdef0123456789abcdef01234567';
const _v1 = '89abcdef0123456789abcdef0123456789abcdef';
const _other = 'fedcba9876543210fedcba9876543210fedcba98';

QueueItem _queued(
  String? downloadId, {
  int id = 1,
  double progress = 0.25,
  DownloadProtocol protocol = DownloadProtocol.torrent,
}) => QueueItem(
  id: id,
  downloadId: downloadId,
  title: 'Release',
  status: QueueStatus.downloading,
  trackedState: TrackedState.downloading,
  severity: QueueSeverity.ok,
  progress: progress,
  sizeLeft: 750,
  protocol: protocol,
);

DownloadProgress _torrent(
  String hash, {
  String? infohashV1,
  String instanceId = 'qb1',
  double progress = 0.5,
  DownloadState state = DownloadState.downloading,
}) => DownloadProgress(
  instanceId: instanceId,
  hash: hash,
  infohashV1: infohashV1,
  progress: progress,
  downSpeed: 1024,
  eta: const Duration(minutes: 5),
  state: state,
);

void main() {
  test('matches the torrent whose hash is the download id', () {
    final wanted = _torrent(_hash);

    expect(
      matchProgress(_queued(_hash), [_torrent(_other), wanted]),
      same(wanted),
    );
  });

  group('ignores case', () {
    // The queue and the client need not write a hash the same way.
    test('of the download id', () {
      final torrent = _torrent(_hash);

      expect(
        matchProgress(_queued(_hash.toUpperCase()), [torrent]),
        same(torrent),
      );
    });

    test('of the torrent hash', () {
      final torrent = _torrent(_hash.toUpperCase());

      expect(matchProgress(_queued(_hash), [torrent]), same(torrent));
    });

    test('of the version 1 hash, on either side', () {
      final lower = _torrent(_hash, infohashV1: _v1);
      final upper = _torrent(_hash, infohashV1: _v1.toUpperCase());

      expect(matchProgress(_queued(_v1.toUpperCase()), [lower]), same(lower));
      expect(matchProgress(_queued(_v1), [upper]), same(upper));
    });
  });

  group('version 1 hash', () {
    // A hybrid torrent: the client's hash is not the version 1 hash.
    final hybrid = _torrent(_hash, infohashV1: _v1);

    test('matches', () {
      expect(matchProgress(_queued(_v1), [hybrid]), same(hybrid));
    });

    test('does not stop the hash from matching', () {
      expect(matchProgress(_queued(_hash), [hybrid]), same(hybrid));
    });
  });

  test('entries of a season pack share one record', () {
    final queue = [
      _queued(_hash.toUpperCase(), id: 1, progress: 0),
      _queued(_hash.toUpperCase(), id: 2, progress: 0.25),
      _queued(_hash, id: 3, progress: 1),
    ];
    final pack = _torrent(_hash, progress: 0.4);
    final torrents = [_torrent(_other, progress: 0.9), pack];

    for (final item in queue) {
      expect(
        matchProgress(item, torrents),
        same(pack),
        reason: 'queue entry ${item.id}',
      );
    }
  });

  group('no match', () {
    final torrents = [_torrent(_hash, infohashV1: _v1)];

    test('when no torrent has the download id', () {
      expect(matchProgress(_queued(_other), torrents), isNull);
    });

    test('for a Usenet download', () {
      final item = _queued(
        'SABnzbd_nzo_abc123',
        protocol: DownloadProtocol.usenet,
      );

      expect(matchProgress(item, torrents), isNull);
    });

    test('for part of a hash, or more than a hash', () {
      for (final id in [
        _hash.substring(0, 20),
        '${_hash}00',
        _v1.substring(1),
      ]) {
        expect(matchProgress(_queued(id), torrents), isNull, reason: id);
      }
    });

    test('without a download id', () {
      // The torrent has no version 1 hash either.
      expect(matchProgress(_queued(null), [_torrent(_hash)]), isNull);
    });

    test('with an empty download id, even against an empty hash', () {
      expect(
        matchProgress(_queued(''), [_torrent(_hash, infohashV1: '')]),
        isNull,
      );
    });

    test('without torrents', () {
      expect(matchProgress(_queued(_hash), const []), isNull);
    });
  });

  group('several clients', () {
    test('finds a torrent that only a later client has', () {
      final wanted = _torrent(_hash, instanceId: 'qb2');

      expect(
        matchProgress(_queued(_hash), [_torrent(_other), wanted]),
        same(wanted),
      );
    });

    test('takes the first client in instance order', () {
      // Neither the further along nor the more active torrent is preferred,
      // and instance ids do not decide the order.
      final first = _torrent(
        _hash,
        instanceId: 'qb-z',
        progress: 0.1,
        state: DownloadState.paused,
      );
      final second = _torrent(_hash, instanceId: 'qb-a', progress: 1);

      expect(matchProgress(_queued(_hash), [first, second]), same(first));
      expect(matchProgress(_queued(_hash), [second, first]), same(second));
    });

    test('keeps instance order across both kinds of hash', () {
      final byV1 = _torrent(_other, infohashV1: _v1);
      final byHash = _torrent(_v1, instanceId: 'qb2');

      expect(matchProgress(_queued(_v1), [byV1, byHash]), same(byV1));
      expect(matchProgress(_queued(_v1), [byHash, byV1]), same(byHash));
    });
  });

  group("gives the client's own figures", () {
    test('progress, not that of the queue entry', () {
      for (final progress in [0.0, 0.5, 1.0]) {
        final match = matchProgress(_queued(_hash, progress: 0.25), [
          _torrent(_hash, progress: progress),
        ]);

        expect(match?.progress, progress);
      }
    });

    test('state, whatever it is', () {
      for (final state in DownloadState.values) {
        final match = matchProgress(_queued(_hash), [
          _torrent(_hash, state: state),
        ]);

        expect(match?.state, state, reason: state.name);
      }
    });
  });
}
