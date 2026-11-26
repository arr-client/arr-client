// Series: the library reads, their states and their cache.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';
import 'support.dart';

Future<Map<int, Series>> _list(Harness harness) async => {
  for (final item in await ok(harness.library.list()))
    item.ref.remoteId: item as Series,
};

/// Series 4 with these statistics and flag, and no queue.
Future<ItemState> _stateWith({
  required int episodeCount,
  required int episodeFileCount,
  required bool monitored,
}) async {
  final harness = Harness();
  harness.server.queue.clear();
  final series = byId(harness.server.series, 4);
  series['monitored'] = monitored;
  series['statistics'] = {
    ...series['statistics']! as Map<String, Object?>,
    'episodeCount': episodeCount,
    'episodeFileCount': episodeFileCount,
  };
  return (await _list(harness))[4]!.state;
}

MediaImage _image(Series series, MediaImageType type) =>
    series.images.singleWhere((image) => image.type == type);

/// Whether the allow-list lets the artwork loader ask for [instancePath].
bool _permitted(String instancePath) {
  final uri = Uri.parse(instancePath);
  return allowList.permits(
    ServiceRequest(HttpMethod.get, uri.path, query: uri.queryParametersAll),
  );
}

void main() {
  test('the library is of series', () {
    expect(Harness().library.itemKind, MediaKind.series);
  });

  group('list', () {
    test('every series, keyed to this instance', () async {
      final items = await ok(Harness().library.list());

      expect(
        items.map((item) => item.ref),
        unorderedEquals([for (var id = 1; id <= 4; id++) seriesRef(id)]),
      );
      expect(items, everyElement(isA<Series>()));
    });

    test('maps the fields of a series', () async {
      final harness = Harness();
      final raw = byId(harness.server.series, 1);

      final series = (await _list(harness))[1]!;

      expect(series.title, raw['title']);
      expect(series.sortTitle, raw['sortTitle']);
      expect(series.year, 1962);
      expect(series.overview, raw['overview']);
      expect(series.network, raw['network']);
      expect(series.status, SeriesStatus.ended);
      expect(series.seriesType, SeriesType.standard);
      expect(series.seasonFolder, isTrue);
      expect(series.runtime, const Duration(minutes: 25));
      expect(series.genres, raw['genres']);
      expect(series.certification, 'TV-G');
      expect(series.ratings.single.value, 7.3);
      expect(series.ratings.single.votes, 12680);
      expect(series.monitored, isTrue);
      expect(series.qualityProfileId, 6);
      expect(series.tagIds, {1});
      expect(series.path, raw['path']);
      expect(series.sizeOnDisk, 438999);
      expect(series.addedAt, DateTime.utc(2026, 11, 26, 12, 51, 34));
      expect(series.parent, isNull);
      expect(series.parentTitle, isNull);
    });

    test('maps the seasons and their counts', () async {
      final seasons = (await _list(Harness()))[1]!.seasons;

      expect(seasons.map((s) => s.number), List.generate(10, (n) => n));
      expect(seasons[0].monitored, isFalse);
      expect(seasons[0].totalEpisodeCount, 12);
      expect(seasons[1].monitored, isTrue);
      expect(seasons[1].episodeCount, 36);
      expect(seasons[1].episodeFileCount, 3);
      expect(seasons[1].totalEpisodeCount, 36);
    });

    test('series type and status', () async {
      final harness = Harness();
      final changes = [
        ('daily', 'continuing'),
        ('anime', 'upcoming'),
        ('standard', 'deleted'),
        ('somethingNew', 'somethingNew'),
      ];
      for (final (index, (type, status)) in changes.indexed) {
        harness.server.series[index]
          ..['seriesType'] = type
          ..['status'] = status;
      }

      final series = await _list(harness);

      expect(
        [
          for (var id = 1; id <= 4; id++)
            (series[id]!.seriesType, series[id]!.status),
        ],
        [
          (SeriesType.daily, SeriesStatus.continuing),
          (SeriesType.anime, SeriesStatus.upcoming),
          (SeriesType.standard, SeriesStatus.deleted),
          (SeriesType.unknown, SeriesStatus.unknown),
        ],
      );
    });

    test('a series without the optional fields', () async {
      final harness = Harness();
      final raw = byId(harness.server.series, 1);
      for (final field in [
        'overview',
        'network',
        'certification',
        'ratings',
        'genres',
        'images',
        'tags',
      ]) {
        raw.remove(field);
      }

      final series = (await _list(harness))[1]!;

      expect(series.overview, isNull);
      expect(series.network, isNull);
      expect(series.certification, isNull);
      expect(series.ratings, isEmpty);
      expect(series.genres, isEmpty);
      expect(series.images, isEmpty);
      expect(series.tagIds, isEmpty);
    });
  });

  group('artwork', () {
    test('a cover is read from the API, keeping its query', () async {
      final series = (await _list(Harness()))[1]!;

      final poster = _image(series, MediaImageType.poster);
      expect(
        poster.instancePath,
        'api/v3/mediacover/1/poster.jpg?lastWrite=639312942949825629',
      );
      expect(poster.remoteUrl?.host, 'redacted.invalid');
      expect(_permitted(poster.instancePath!), isTrue);
      expect(
        _image(series, MediaImageType.banner).instancePath,
        startsWith('api/v3/mediacover/1/banner.jpg?'),
      );
      expect(
        _image(series, MediaImageType.fanart).instancePath,
        startsWith('api/v3/mediacover/1/fanart.jpg?'),
      );
    });

    test('other artwork is of another type', () async {
      final series = (await _list(Harness()))[4]!;

      expect(
        _image(series, MediaImageType.other).instancePath,
        startsWith('api/v3/mediacover/4/clearlogo.png?'),
      );
    });

    // The server's URL base is already part of the instance's address, and
    // Sonarr 5 names the cache buster `h`.
    test('under a URL base, with the query of Sonarr 5', () async {
      final harness = Harness();
      byId(harness.server.series, 1)['images'] = [
        {
          'coverType': 'poster',
          'url': '/sonarr/MediaCover/1/poster.jpg?h=0123456789abcdef0123',
        },
      ];

      final poster = (await _list(harness))[1]!.images.single;

      expect(
        poster.instancePath,
        'api/v3/mediacover/1/poster.jpg?h=0123456789abcdef0123',
      );
      expect(poster.remoteUrl, isNull);
      expect(_permitted(poster.instancePath!), isTrue);
    });

    test(
      'artwork the server has not stored keeps its remote address',
      () async {
        final harness = Harness();
        byId(harness.server.series, 1)['images'] = [
          {
            'coverType': 'poster',
            'remoteUrl': 'https://art.example.test/1.jpg',
          },
        ];

        final poster = (await _list(harness))[1]!.images.single;

        expect(poster.instancePath, isNull);
        expect(poster.remoteUrl, Uri.parse('https://art.example.test/1.jpg'));
      },
    );
  });

  // data-model.md LibraryItem.state and ItemState.resolve.
  group('state', () {
    test('of the recorded library and queue', () async {
      final series = await _list(Harness());

      expect(series.map((id, s) => MapEntry(id, s.state)), {
        // Episodes of it are in the queue.
        1: ItemState.downloading,
        // Not monitored, no files.
        2: ItemState.unmonitored,
        // Monitored for future episodes only, none of them released.
        3: ItemState.unreleased,
        4: ItemState.missing,
      });
    });

    test('some files and nothing in the queue is partial', () async {
      final harness = Harness();
      harness.server.queue.clear();

      expect((await _list(harness))[1]!.state, ItemState.partial);
    });

    test('every wanted episode present is downloaded', () async {
      for (final monitored in [true, false]) {
        expect(
          await _stateWith(
            episodeCount: 26,
            episodeFileCount: 26,
            monitored: monitored,
          ),
          ItemState.downloaded,
        );
      }
    });

    test('partial comes before unmonitored', () async {
      expect(
        await _stateWith(
          episodeCount: 26,
          episodeFileCount: 1,
          monitored: false,
        ),
        ItemState.partial,
      );
    });

    test('an unmonitored series without files', () async {
      expect(
        await _stateWith(
          episodeCount: 26,
          episodeFileCount: 0,
          monitored: false,
        ),
        ItemState.unmonitored,
      );
    });

    test('any entry in the queue is downloading, even a delayed one', () async {
      final harness = Harness();
      final delayed = harness.server.queue.singleWhere(
        (item) => item['status'] == 'delay',
      );
      delayed['seriesId'] = 2;
      harness.server.queue
        ..clear()
        ..add(delayed);

      final series = await _list(harness);

      expect(series[2]!.state, ItemState.downloading);
      expect(series[4]!.state, ItemState.missing);
    });
  });

  group('one series', () {
    test('is read by its id', () async {
      final harness = Harness();

      final series = await ok(harness.library.item(seriesRef(1))) as Series;

      expect(series.ref, seriesRef(1));
      expect(series.title, byId(harness.server.series, 1)['title']);
      expect(series.state, ItemState.downloading);
      expect(series.seasons, hasLength(10));
      expect(
        harness.server.requests.map((r) => r.path),
        contains('api/v3/series/1'),
      );
    });

    test('deleted on the server is not found and leaves the cache', () async {
      final harness = Harness();
      await ok(harness.library.list());
      await ok(harness.library.children(seriesRef(1)));
      harness.server.series.removeWhere((s) => s['id'] == 1);
      harness.server.episodes.remove(1);

      expect(
        await failureOf(harness.library.item(seriesRef(1))),
        isA<NotFound>(),
      );

      expect(await ok(harness.library.cachedItem(seriesRef(1))), isNull);
      expect(await ok(harness.library.cachedChildren(seriesRef(1))), isNull);
      final list = await ok(harness.library.cachedList());
      expect(
        list!.value.map((item) => item.ref),
        isNot(contains(seriesRef(1))),
      );
    });
  });

  test('Sonarr provides no credits and none are asked for', () async {
    final harness = Harness();

    expect(await ok(harness.library.credits(seriesRef(1))), isEmpty);
    expect(harness.server.requests, isEmpty);
  });

  group('failures', () {
    for (final (name, answer, failure) in [
      ('a rejected key', FakeSonarr.body('', status: 401), isA<AuthFailed>()),
      (
        'a proxy page',
        FakeSonarr.body('<html></html>', contentType: 'text/html'),
        isA<ProxyInterception>(),
      ),
      ('cut off JSON', FakeSonarr.body('[{"id": 1'), isA<MalformedResponse>()),
      ('an object for a list', FakeSonarr.body('{}'), isA<MalformedResponse>()),
      (
        'records of another shape',
        FakeSonarr.body('[1, 2]'),
        isA<MalformedResponse>(),
      ),
    ]) {
      test('$name is a failure and keeps the cache', () async {
        final harness = Harness();
        await ok(harness.library.list());
        harness.server.overrides['series'] = answer;

        expect(await failureOf(harness.library.list()), failure);

        final cached = await ok(harness.library.cachedList());
        expect(cached!.value, hasLength(4));
      });
    }

    test('an unreachable server', () async {
      final harness = Harness()..server.goOffline();

      expect(await failureOf(harness.library.list()), isA<Unreachable>());
      expect(
        await failureOf(harness.library.item(seriesRef(1))),
        isA<Unreachable>(),
      );
      expect(await ok(harness.library.cachedList()), isNull);
    });
  });

  group('cache', () {
    test('holds nothing before the first fetch', () async {
      final harness = Harness();

      expect(await ok(harness.library.cachedList()), isNull);
      expect(await ok(harness.library.cachedItem(seriesRef(1))), isNull);
      expect(harness.server.requests, isEmpty);
    });

    test('returns the list offline, as fetched and with its age', () async {
      final before = DateTime.now().toUtc();
      final first = Harness();
      final fetched = await _list(first);
      final after = DateTime.now().toUtc();

      // A later launch: another module and adapter over the same cache.
      final later = Harness(cache: first.cache);
      later.server.goOffline();
      final cached = (await ok(later.library.cachedList()))!;

      expect(later.server.requests, isEmpty);
      expect(cached.fetchedAt.isBefore(before), isFalse);
      expect(cached.fetchedAt.isAfter(after), isFalse);
      expect(cached.value, hasLength(4));
      for (final item in cached.value) {
        final series = item as Series;
        final was = fetched[series.ref.remoteId]!;
        expect(series.ref, was.ref);
        expect(series.title, was.title);
        expect(series.sortTitle, was.sortTitle);
        expect(series.state, was.state);
        expect(series.monitored, was.monitored);
        expect(series.qualityProfileId, was.qualityProfileId);
        expect(series.tagIds, was.tagIds);
        expect(series.addedAt, was.addedAt);
        expect(series.sizeOnDisk, was.sizeOnDisk);
        expect(series.status, was.status);
        expect(series.seasons.map((s) => s.number), [
          for (final season in was.seasons) season.number,
        ]);
        expect(series.images.map((i) => i.instancePath), [
          for (final image in was.images) image.instancePath,
        ]);
      }
    });

    test('stores the summary and the record as the server sent it', () async {
      final harness = Harness();
      byId(harness.server.series, 1)['aFieldTheAppDoesNotKnow'] = 'kept';

      await ok(harness.library.list());

      final entry = (await harness.cache.entry(MediaKind.series, 1))!;
      expect(entry.sortTitle, byId(harness.server.series, 1)['sortTitle']);
      expect(entry.state, ItemState.downloading);
      expect(entry.monitored, isTrue);
      expect(entry.qualityProfileId, 6);
      expect(entry.tagIds, [1]);
      expect(entry.addedAt, DateTime.utc(2026, 11, 26, 12, 51, 34));
      expect(entry.parentRemoteId, isNull);
      expect(
        jsonDecode(entry.rawJson),
        containsPair('aFieldTheAppDoesNotKnow', 'kept'),
      );
    });

    test('drops a series the server no longer lists', () async {
      final harness = Harness();
      await ok(harness.library.list());
      harness.server.series.removeWhere((s) => s['id'] == 2);

      await ok(harness.library.list());

      final cached = (await ok(harness.library.cachedList()))!;
      expect(
        cached.value.map((item) => item.ref.remoteId),
        unorderedEquals([1, 3, 4]),
      );
    });

    test('an empty library is not one never fetched', () async {
      final harness = Harness();
      harness.server.series.clear();

      expect(await ok(harness.library.list()), isEmpty);

      expect((await ok(harness.library.cachedList()))!.value, isEmpty);
    });

    test('keeps one series that was read', () async {
      final harness = Harness();
      await ok(harness.library.item(seriesRef(4)));
      harness.server.goOffline();

      final cached = (await ok(harness.library.cachedItem(seriesRef(4))))!;

      expect(cached.value.ref, seriesRef(4));
      expect(cached.value.state, ItemState.missing);
    });
  });
}
