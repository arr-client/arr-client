// Episodes and their files.
//
// Recorded series 1: episodes 13, 14 and 17 have files; 14 and 16 to 20 are in
// the queue; 1 and 2 are unmonitored specials, 1 without an air date.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _all = [1, 2, 13, 14, 15, 16, 17, 18, 19, 20, 49, 50];

Future<Map<int, Episode>> _children(Harness harness) async => {
  for (final item in await ok(harness.library.children(seriesRef(1))))
    item.ref.remoteId: item as Episode,
};

/// The state of episode 15, which has no file, after [changes] and without a
/// queue.
Future<ItemState> _stateWith(Map<String, Object?> changes) async {
  final harness = Harness();
  harness.server.queue.clear();
  byId(harness.server.episodes[1]!, 15).addAll(changes);
  return (await _children(harness))[15]!.state;
}

void _expectFirstFile(MediaFile file, Map<String, Object?> raw) {
  expect(file.id, 1);
  expect(file.path, raw['path']);
  expect(file.size, 146333);
  expect(file.quality?.id, 4);
  expect(file.quality?.name, 'HDTV-720p');
  expect(file.languages.map((l) => (l.id, l.name)), [(1, 'English')]);
  expect(file.video, contains('x264'));
  expect(file.audio, contains('AAC'));
}

void main() {
  group('children of a series', () {
    test('are its episodes, each under the series', () async {
      final harness = Harness();
      final title = byId(harness.server.series, 1)['title'];

      final episodes = await _children(harness);

      expect(episodes.keys, unorderedEquals(_all));
      for (final episode in episodes.values) {
        expect(episode.ref, episodeRef(episode.ref.remoteId));
        expect(episode.parent, seriesRef(1));
        expect(episode.parentTitle, title);
      }
    });

    test('maps the fields of an episode', () async {
      final harness = Harness();
      final raw = byId(harness.server.episodes[1]!, 13);

      final episode = (await _children(harness))[13]!;

      expect(episode.title, raw['title']);
      expect(episode.overview, raw['overview']);
      expect(episode.seasonNumber, 1);
      expect(episode.episodeNumber, 1);
      expect(episode.airDateUtc, DateTime.utc(1962, 9, 26, 23, 30));
      expect(episode.airDateUtc!.isUtc, isTrue);
      expect(episode.monitored, isTrue);
      expect(episode.hasFile, isTrue);
    });

    test('an episode with a file carries its details', () async {
      final harness = Harness();
      final raw = byId(harness.server.episodeFiles[1]!, 1);

      final episodes = await _children(harness);

      _expectFirstFile(episodes[13]!.file!, raw);
      expect(episodes[13]!.sizeOnDisk, 146333);
      expect(episodes[15]!.hasFile, isFalse);
      expect(episodes[15]!.file, isNull);
    });

    test('specials are season 0 and may have no air date', () async {
      final special = (await _children(Harness()))[1]!;

      expect(special.seasonNumber, 0);
      expect(special.airDateUtc, isNull);
    });

    test('a screenshot is loaded from its remote address', () async {
      final image = (await _children(Harness()))[13]!.images.single;

      expect(image.type, MediaImageType.other);
      expect(image.instancePath, isNull);
      expect(image.remoteUrl?.host, 'redacted.invalid');
    });
  });

  group('state', () {
    test('of the recorded episodes and queue', () async {
      final episodes = await _children(Harness());

      expect(episodes.map((id, e) => MapEntry(id, e.state)), {
        1: ItemState.unmonitored,
        2: ItemState.unmonitored,
        13: ItemState.downloaded,
        // Has a file, and an upgrade in the queue.
        14: ItemState.downloading,
        15: ItemState.missing,
        16: ItemState.downloading,
        // Completed, waiting to be imported.
        17: ItemState.downloading,
        // One release of two episodes.
        18: ItemState.downloading,
        19: ItemState.downloading,
        // Delayed.
        20: ItemState.downloading,
        49: ItemState.missing,
        50: ItemState.missing,
      });
    });

    test('without the queue', () async {
      final harness = Harness();
      harness.server.queue.clear();

      final episodes = await _children(harness);

      expect(episodes[14]!.state, ItemState.downloaded);
      expect(episodes[16]!.state, ItemState.missing);
    });

    test('a file counts whether or not the episode is monitored', () async {
      expect(
        await _stateWith({'hasFile': true, 'monitored': false}),
        ItemState.downloaded,
      );
    });

    test('not yet aired is unreleased', () async {
      expect(
        await _stateWith({'airDateUtc': '2099-01-01T00:00:00Z'}),
        ItemState.unreleased,
      );
      expect(await _stateWith({'airDateUtc': null}), ItemState.unreleased);
    });

    test('unmonitored comes before unreleased', () async {
      expect(
        await _stateWith({
          'monitored': false,
          'airDateUtc': '2099-01-01T00:00:00Z',
        }),
        ItemState.unmonitored,
      );
    });
  });

  group('one episode', () {
    test('with its series and file', () async {
      final harness = Harness();
      final raw = byId(harness.server.episodeFiles[1]!, 1);

      final episode = await ok(harness.library.item(episodeRef(13))) as Episode;

      expect(episode.ref, episodeRef(13));
      expect(episode.parent, seriesRef(1));
      expect(episode.parentTitle, byId(harness.server.series, 1)['title']);
      expect(episode.state, ItemState.downloaded);
      _expectFirstFile(episode.file!, raw);
    });

    test('in the queue is downloading', () async {
      final episode = await ok(Harness().library.item(episodeRef(16)));

      expect(episode.state, ItemState.downloading);
    });

    // Sonarr answers an unknown episode id with 500, not 404.
    test('deleted on the server is not found', () async {
      final harness = Harness();
      await ok(harness.library.children(seriesRef(1)));
      harness.server.episodes[1]!.removeWhere((e) => e['id'] == 15);

      expect(
        await failureOf(harness.library.item(episodeRef(15))),
        isA<NotFound>(),
      );

      expect(await ok(harness.library.cachedItem(episodeRef(15))), isNull);
    });

    test('another server error is not taken for a deletion', () async {
      final harness = Harness();
      await ok(harness.library.children(seriesRef(1)));
      harness.server.always = FakeSonarr.body(
        '{"message": "database is locked"}',
        status: 500,
      );

      expect(
        await failureOf(harness.library.item(episodeRef(15))),
        isA<ServerError>(),
      );

      expect(await ok(harness.library.cachedItem(episodeRef(15))), isNotNull);
    });
  });

  // Sonarr answers the episodes of an unknown series with an empty list.
  test('children of a deleted series are not found', () async {
    final harness = Harness();
    await ok(harness.library.list());
    await ok(harness.library.children(seriesRef(1)));
    harness.server.series.removeWhere((s) => s['id'] == 1);
    harness.server.episodes.remove(1);
    harness.server.episodeFiles.remove(1);

    expect(
      await failureOf(harness.library.children(seriesRef(1))),
      isA<NotFound>(),
    );

    expect(await ok(harness.library.cachedChildren(seriesRef(1))), isNull);
  });

  group('files', () {
    test('of a series', () async {
      final harness = Harness();
      final raw = byId(harness.server.episodeFiles[1]!, 1);

      final files = await ok(harness.library.files(seriesRef(1)));

      expect(
        files.map((file) => file.id),
        unorderedEquals([
          for (final file in harness.server.episodeFiles[1]!) file['id'],
        ]),
      );
      _expectFirstFile(files.singleWhere((file) => file.id == 1), raw);
    });

    test('of an episode', () async {
      final harness = Harness();
      final raw = byId(harness.server.episodeFiles[1]!, 1);

      final files = await ok(harness.library.files(episodeRef(13)));

      _expectFirstFile(files.single, raw);
    });

    test('of an episode without one', () async {
      expect(await ok(Harness().library.files(episodeRef(15))), isEmpty);
    });

    test('without media information', () async {
      final harness = Harness();
      byId(harness.server.episodeFiles[1]!, 1).remove('mediaInfo');

      final files = await ok(harness.library.files(seriesRef(1)));

      final file = files.singleWhere((file) => file.id == 1);
      expect(file.video, isNull);
      expect(file.audio, isNull);
    });

    test('of a deleted series are not found', () async {
      expect(
        await failureOf(Harness().library.files(seriesRef(999))),
        isA<NotFound>(),
      );
    });
  });

  group('cache', () {
    test('holds nothing before the first fetch', () async {
      final harness = Harness();

      expect(await ok(harness.library.cachedChildren(seriesRef(1))), isNull);
      expect(await ok(harness.library.cachedItem(episodeRef(13))), isNull);
      expect(harness.server.requests, isEmpty);
    });

    test('returns episodes and their files offline', () async {
      final first = Harness();
      final raw = byId(first.server.episodeFiles[1]!, 1);
      await ok(first.library.list());
      final fetched = await _children(first);

      final later = Harness(cache: first.cache);
      later.server.goOffline();
      final cached = (await ok(later.library.cachedChildren(seriesRef(1))))!;
      final one = (await ok(later.library.cachedItem(episodeRef(13))))!;

      expect(later.server.requests, isEmpty);
      expect(cached.value, hasLength(_all.length));
      for (final item in cached.value) {
        final episode = item as Episode;
        final was = fetched[episode.ref.remoteId]!;
        expect(episode.title, was.title);
        expect(episode.state, was.state);
        expect(episode.seasonNumber, was.seasonNumber);
        expect(episode.episodeNumber, was.episodeNumber);
        expect(episode.airDateUtc, was.airDateUtc);
        expect(episode.hasFile, was.hasFile);
        expect(episode.parent, seriesRef(1));
        expect(episode.parentTitle, was.parentTitle);
      }
      _expectFirstFile((one.value as Episode).file!, raw);
    });

    test('files the episodes under their series', () async {
      final harness = Harness();

      await ok(harness.library.children(seriesRef(1)));
      await ok(harness.library.children(seriesRef(4)));

      final entry = (await harness.cache.entry(MediaKind.episode, 13))!;
      expect(entry.parentRemoteId, 1);
      final first = await ok(harness.library.cachedChildren(seriesRef(1)));
      expect(first!.value, hasLength(_all.length));
      final other = await ok(harness.library.cachedChildren(seriesRef(4)));
      expect(other!.value, hasLength(3));
    });

    test('drops an episode the server no longer lists', () async {
      final harness = Harness();
      await ok(harness.library.children(seriesRef(1)));
      harness.server.episodes[1]!.removeWhere((e) => e['id'] == 50);

      await ok(harness.library.children(seriesRef(1)));

      final cached = await ok(harness.library.cachedChildren(seriesRef(1)));
      expect(cached!.value, hasLength(_all.length - 1));
    });
  });
}
