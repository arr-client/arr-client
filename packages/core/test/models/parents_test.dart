import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

ItemRef _ref(MediaKind kind, int id) =>
    ItemRef(instanceId: 'i1', kind: kind, remoteId: id);

QueueItem _queued(int id, {required ItemRef item, required ItemRef parent}) =>
    QueueItem(
      id: id,
      itemRef: item,
      parent: parent,
      title: 'Release $id',
      status: QueueStatus.completed,
      trackedState: TrackedState.importPending,
      severity: QueueSeverity.warning,
      progress: 1,
      sizeLeft: 0,
      protocol: DownloadProtocol.torrent,
    );

void main() {
  test('an episode in a flat list names its series', () {
    final LibraryItem episode = Episode(
      ref: _ref(MediaKind.episode, 7),
      parent: _ref(MediaKind.series, 1),
      parentTitle: 'The series',
      title: 'Pilot',
      sortTitle: 'pilot',
      seasonNumber: 1,
      episodeNumber: 1,
      monitored: true,
      state: ItemState.missing,
      hasFile: false,
    );

    expect(episode.parent, _ref(MediaKind.series, 1));
    expect(episode.parentTitle, 'The series');
  });

  test("a series' queue entries are found by their parent", () {
    final series = _ref(MediaKind.series, 1);
    final queue = [
      _queued(1, item: _ref(MediaKind.episode, 7), parent: series),
      _queued(
        2,
        item: _ref(MediaKind.episode, 8),
        parent: _ref(MediaKind.series, 2),
      ),
    ];

    expect(
      [
        for (final entry in queue)
          if (entry.parent == series) entry.id,
      ],
      [1],
    );
  });
}
