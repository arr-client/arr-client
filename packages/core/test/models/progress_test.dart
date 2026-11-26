import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

QueueItem _queued(double progress) => QueueItem(
  id: 1,
  title: 'Release',
  status: QueueStatus.downloading,
  trackedState: TrackedState.downloading,
  severity: QueueSeverity.ok,
  progress: progress,
  sizeLeft: 0,
  protocol: DownloadProtocol.torrent,
);

DownloadProgress _torrent(double progress) => DownloadProgress(
  instanceId: 'i1',
  hash: 'abc',
  progress: progress,
  downSpeed: 0,
  state: DownloadState.downloading,
);

void main() {
  group('queue item progress', () {
    double of(num size, num sizeLeft) =>
        QueueItem.progressFrom(size: size, sizeLeft: sizeLeft);

    test('is the share of the bytes already there', () {
      expect(of(200, 200), 0);
      expect(of(200, 50), 0.75);
      expect(of(200, 0), 1);
    });

    test('is 0 while the size is not known', () {
      expect(of(0, 0), 0);
      expect(of(-1, 0), 0);
      expect(of(double.nan, 0), 0);
    });

    test('stays within 0 to 1 when the figures disagree', () {
      expect(of(100, 150), 0);
      expect(of(100, -1), 1);
      expect(of(100, double.nan), 0);
      expect(of(double.infinity, 0), 0);
    });
  });

  test('download client progress stays within 0 to 1', () {
    expect(DownloadProgress.progressFrom(0.5), 0.5);
    expect(DownloadProgress.progressFrom(1), 1);
    expect(DownloadProgress.progressFrom(-0.1), 0);
    expect(DownloadProgress.progressFrom(1.1), 1);
    expect(DownloadProgress.progressFrom(double.nan), 0);
  });

  test('a record rejects progress outside 0 to 1', () {
    for (final progress in [0.0, 1.0]) {
      expect(_queued(progress).progress, progress);
      expect(_torrent(progress).progress, progress);
    }
    for (final progress in [-0.1, 1.1, double.nan]) {
      expect(() => _queued(progress), throwsA(isA<AssertionError>()));
      expect(() => _torrent(progress), throwsA(isA<AssertionError>()));
    }
  });
}
