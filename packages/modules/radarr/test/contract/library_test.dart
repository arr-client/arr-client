// LibraryProvider reads of movies against recorded answers (spec story 2).

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import '../allow_list.dart';
import 'library_support.dart';

Future<Movie> _item(Harness harness, int id) async =>
    await succeed(harness.library.item(movieRef(id))) as Movie;

/// Movie 1 as listed, with [changes] applied, read back through the module.
Future<Movie> _changed(Map<String, Object?> changes) async {
  final harness = Harness();
  harness.server.movies = [
    {...recorded('movie', 1), ...changes},
  ];
  return byId(await succeed(harness.library.list()))[1]!;
}

/// [path] of an image must be a read the allow-list has.
bool _permitted(String path) {
  final uri = Uri.parse(path);
  return allowList.permits(
    ServiceRequest(HttpMethod.get, uri.path, query: uri.queryParametersAll),
  );
}

void _expectDate(DateTime? actual, Object? wire) {
  if (wire == null) {
    expect(actual, isNull);
  } else {
    expect(actual?.toUtc(), DateTime.parse(wire as String));
  }
}

void main() {
  test('is a movie library with no monitoring options', () {
    final library = Harness().library;

    expect(library.itemKind, MediaKind.movie);
    // The contract: monitoring of a movie is a toggle only.
    expect(library.monitorOptions, isEmpty);
  });

  test('offers the capabilities it has, and no request', () {
    final harness = Harness();
    final module = RadarrModule();

    final offered = module.capabilitiesFor(
      const ProbeResult(
        product: 'Radarr',
        version: '7.0.3.10918',
        newerThanTested: false,
      ),
      null,
    );

    expect(offered, {
      CapabilityKind.library,
      CapabilityKind.lookup,
      CapabilityKind.queue,
      CapabilityKind.history,
      CapabilityKind.wanted,
      CapabilityKind.calendar,
      CapabilityKind.health,
    });
    for (final kind in CapabilityKind.values) {
      expect(
        kind.of(module, harness.context),
        offered.contains(kind) ? isNotNull : isNull,
        reason: kind.name,
      );
    }
    expect(harness.server.requests, isEmpty);
  });

  group('list', () {
    test('asks for the movies and only reads', () async {
      final harness = Harness();

      await succeed(harness.library.list());

      final paths = harness.server.requests.map((r) => r.path);
      expect(paths.where((path) => path == 'api/v3/movie'), hasLength(1));
      expect(harness.server.requests.map((r) => r.method).toSet(), {
        HttpMethod.get,
      });
    });

    test('gives every movie of the instance', () async {
      final movies = byId(await succeed(Harness().library.list()));

      expect(movies.keys, unorderedEquals([1, 2, 3, 4, 5, 6, 7]));
      for (final MapEntry(key: id, value: movie) in movies.entries) {
        expect(movie.ref, movieRef(id));
        expect(movie.title, recorded('movie', id)['title']);
        expect(movie.parent, isNull);
        expect(movie.parentTitle, isNull);
      }
    });

    test('maps the fields of a movie', () async {
      final wire = recorded('movie', 1);

      final movie = byId(await succeed(Harness().library.list()))[1]!;

      expect(movie.title, wire['title']);
      expect(movie.sortTitle, wire['sortTitle']);
      expect(movie.year, 2008);
      expect(movie.overview, wire['overview']);
      expect(movie.monitored, isTrue);
      expect(movie.qualityProfileId, 4);
      expect(movie.tagIds, {1});
      expect(movie.path, wire['path']);
      expect(movie.sizeOnDisk, 21805813);
      _expectDate(movie.addedAt, wire['added']);
      expect(movie.runtime, const Duration(minutes: 8));
      expect(movie.genres, wire['genres']);
      expect(movie.certification, 'G');
      expect(movie.studio, wire['studio']);
      expect(movie.minimumAvailability, MinimumAvailability.released);
    });

    test('maps the release dates', () async {
      final movies = byId(await succeed(Harness().library.list()));

      // 3 has all three, 5 only the cinema date.
      for (final id in [1, 3, 5, 6]) {
        final wire = recorded('movie', id);
        _expectDate(movies[id]!.inCinemas, wire['inCinemas']);
        _expectDate(movies[id]!.digitalRelease, wire['digitalRelease']);
        _expectDate(movies[id]!.physicalRelease, wire['physicalRelease']);
      }
    });

    test('maps each rating with its source', () async {
      final movie = byId(await succeed(Harness().library.list()))[3]!;

      final ratings = {for (final r in movie.ratings) r.source: r};
      expect(
        ratings.keys,
        unorderedEquals([
          'imdb',
          'tmdb',
          'metacritic',
          'rottenTomatoes',
          'trakt',
        ]),
      );
      expect(ratings['imdb']!.value, 7.8);
      expect(ratings['imdb']!.votes, 153670);
      // A whole number on the wire.
      expect(ratings['metacritic']!.value, 89);
    });

    test('takes a runtime of zero as unknown', () async {
      final movies = byId(await succeed(Harness().library.list()));

      expect(movies[5]!.runtime, isNull);
      expect(movies[5]!.certification, isNull);
    });

    test('maps the minimum availability', () async {
      for (final (wire, expected) in [
        ('tba', MinimumAvailability.tba),
        ('announced', MinimumAvailability.announced),
        ('inCinemas', MinimumAvailability.inCinemas),
        ('released', MinimumAvailability.released),
        ('someFutureValue', MinimumAvailability.unknown),
      ]) {
        final movie = await _changed({'minimumAvailability': wire});

        expect(movie.minimumAvailability, expected, reason: wire);
      }
    });

    test('ignores fields and values it does not know', () async {
      final movie = await _changed({
        'someFutureField': {'a': 1},
        'status': 'someFutureStatus',
      });

      expect(movie.title, recorded('movie', 1)['title']);
    });

    test('does without the optional fields', () async {
      final harness = Harness();
      harness.server.movies = [
        {'id': 9, 'title': 'Bare', 'sortTitle': 'bare', 'monitored': true},
      ];

      final movie = byId(await succeed(harness.library.list()))[9]!;

      expect(movie.year, isNull);
      expect(movie.overview, isNull);
      expect(movie.images, isEmpty);
      expect(movie.tagIds, isEmpty);
      expect(movie.genres, isEmpty);
      expect(movie.ratings, isEmpty);
      expect(movie.sizeOnDisk, 0);
      expect(movie.addedAt, isNull);
      expect(movie.file, isNull);
      expect(movie.minimumAvailability, MinimumAvailability.unknown);
    });
  });

  group('file of a movie', () {
    test('is the one the server embeds', () async {
      final wire = recorded('movie', 1)['movieFile']! as Map<String, Object?>;

      final file = byId(await succeed(Harness().library.list()))[1]!.file!;

      expect(file.id, 4);
      expect(file.path, wire['path']);
      expect(file.size, 21805813);
      expect(file.quality?.id, 7);
      expect(file.quality?.name, 'Bluray-1080p');
      expect(file.languages.map((l) => (l.id, l.name)), [(1, 'English')]);
      // The contract leaves the text open.
      expect(file.video, contains('x264'));
      expect(file.audio, contains('AC3'));
    });

    test('is absent without one', () async {
      final movies = byId(await succeed(Harness().library.list()));

      expect(movies[3]!.file, isNull);
    });
  });

  group('artwork', () {
    test('uses the listed read of the instance', () async {
      final movie = byId(await succeed(Harness().library.list()))[1]!;
      final wire = records(recorded('movie', 1)['images']);

      expect(movie.images.map((i) => i.type), [
        MediaImageType.poster,
        MediaImageType.fanart,
      ]);
      expect(movie.images.map((i) => i.instancePath), [
        'api/v3/mediacover/1/poster.jpg?h=575804ada86e356966a7',
        'api/v3/mediacover/1/fanart.jpg?h=a54364feca427354955c',
      ]);
      expect(movie.images.map((i) => i.remoteUrl), [
        for (final image in wire) Uri.parse(image['remoteUrl']! as String),
      ]);
      for (final image in movie.images) {
        expect(_permitted(image.instancePath!), isTrue);
      }
    });

    Future<MediaImage> image(Map<String, Object?> wire) async =>
        (await _changed({
          'images': [wire],
        })).images.single;

    test('drops the URL base and keeps an older query', () async {
      final result = await image({
        'coverType': 'poster',
        'url': '/radarr/MediaCover/1/poster.jpg?lastWrite=638000000000000000',
      });

      expect(
        result.instancePath,
        'api/v3/mediacover/1/poster.jpg?lastWrite=638000000000000000',
      );
      expect(_permitted(result.instancePath!), isTrue);
      expect(result.remoteUrl, isNull);
    });

    test('takes a cover without a query', () async {
      final result = await image({
        'coverType': 'banner',
        'url': '/MediaCover/1/banner.jpg',
      });

      expect(result.type, MediaImageType.banner);
      expect(result.instancePath, 'api/v3/mediacover/1/banner.jpg');
    });

    test('does not ask the instance for a proxied cover', () async {
      final result = await image({
        'coverType': 'poster',
        'url': '/MediaCoverProxy/0123456789abcdef/poster.jpg',
        'remoteUrl': 'https://image.tmdb.org/t/p/original/poster.jpg',
      });

      expect(result.instancePath, isNull);
      expect(
        result.remoteUrl,
        Uri.parse('https://image.tmdb.org/t/p/original/poster.jpg'),
      );
    });

    test('keeps an image the server has no copy of', () async {
      final result = await image({
        'coverType': 'someFutureType',
        'remoteUrl': 'https://image.tmdb.org/t/p/original/other.jpg',
      });

      expect(result.type, MediaImageType.other);
      expect(result.instancePath, isNull);
      expect(result.remoteUrl, isNotNull);
    });
  });

  // Queued movies are in queue_state_test.dart.
  group('state with an empty queue', () {
    test('follows file, monitoring and availability', () async {
      final movies = byId(await succeed(Harness().library.list()));

      expect(
        {for (final MapEntry(:key, :value) in movies.entries) key: value.state},
        {
          1: ItemState.downloaded,
          // Not monitored, but it has its file.
          2: ItemState.downloaded,
          3: ItemState.missing,
          4: ItemState.unmonitored,
          5: ItemState.unreleased,
          6: ItemState.missing,
          7: ItemState.missing,
        },
      );
    });

    test('puts unmonitored before unreleased', () async {
      final movie = await _changed({
        'hasFile': false,
        'movieFile': null,
        'monitored': false,
        'isAvailable': false,
      });

      expect(movie.state, ItemState.unmonitored);
    });

    test('takes availability from the server', () async {
      // Radarr can hold a released movie back by its availability delay.
      final movie = await _changed({
        'hasFile': false,
        'movieFile': null,
        'status': 'released',
        'isAvailable': false,
      });

      expect(movie.state, ItemState.unreleased);
    });
  });

  group('one movie', () {
    test('is read by its id', () async {
      final harness = Harness();

      final movie = await _item(harness, 1);

      expect(
        harness.server.requests.map((r) => r.path),
        contains('api/v3/movie/1'),
      );
      expect(movie.ref, movieRef(1));
      expect(movie.title, recorded('movie', 1)['title']);
      expect(movie.file?.id, 4);
      expect(movie.state, ItemState.downloaded);
    });

    test('that the server no longer has is not found', () async {
      final harness = Harness();

      final failure = await failureOf(harness.library.item(movieRef(999)));

      expect(failure, isA<NotFound>());
    });
  });

  group('files', () {
    test('asks for the files of the movie', () async {
      final harness = Harness();
      final wire = records(fixture('moviefile')).single;

      final files = await succeed(harness.library.files(movieRef(1)));

      final request = harness.server.requests.single;
      expect(request.path, 'api/v3/moviefile');
      expect(request.query, {
        'movieId': ['1'],
      });
      final file = files.single;
      expect(file.id, 4);
      expect(file.path, wire['path']);
      expect(file.size, 21805813);
      expect(file.quality?.name, 'Bluray-1080p');
      expect(file.languages.single.name, 'English');
      expect(file.video, contains('x264'));
      expect(file.audio, contains('AC3'));
    });

    test('is empty for a movie without one', () async {
      final files = await succeed(Harness().library.files(movieRef(3)));

      expect(files, isEmpty);
    });

    test('does without media information', () async {
      final harness = Harness();
      harness.server.answers['api/v3/moviefile'] = jsonAnswer([
        {
          ...records(fixture('moviefile')).single,
          'mediaInfo': null,
          'languages': null,
        },
      ]);

      final file = (await succeed(harness.library.files(movieRef(1)))).single;

      expect(file.video, isNull);
      expect(file.audio, isNull);
      expect(file.languages, isEmpty);
    });
  });

  group('cache', () {
    test('has nothing before a fetch, and asks no server', () async {
      final harness = Harness();

      expect(await succeed(harness.library.cachedList()), isNull);
      expect(await succeed(harness.library.cachedItem(movieRef(1))), isNull);
      expect(harness.server.requests, isEmpty);
    });

    test('is filled by a list', () async {
      final harness = Harness();
      final wire = recorded('movie', 1);

      await succeed(harness.library.list());

      expect(harness.cache.entries, hasLength(7));
      final entry = harness.cache.entries[(MediaKind.movie, 1)]!;
      expect(entry.parentRemoteId, isNull);
      expect(entry.sortTitle, wire['sortTitle']);
      expect(entry.state, ItemState.downloaded);
      expect(entry.monitored, isTrue);
      expect(entry.qualityProfileId, 4);
      expect(entry.tagIds, [1]);
      _expectDate(entry.addedAt, wire['added']);
      // As received, unknown fields included.
      expect(jsonDecode(entry.rawJson), wire);
    });

    test('is read back without a request', () async {
      final harness = Harness();
      final fetched = byId(await succeed(harness.library.list()));
      harness.server
        ..down = failedAnswer(const Unreachable())
        ..requests.clear();

      final cached = await succeed(harness.library.cachedList());

      expect(harness.server.requests, isEmpty);
      expect(cached!.fetchedAt, FakeCache.listFetchedAt);
      final movies = byId(cached.value);
      expect(movies.keys, unorderedEquals(fetched.keys));
      for (final MapEntry(key: id, value: movie) in movies.entries) {
        expect(movie.ref, movieRef(id));
        expect(movie.title, fetched[id]!.title);
        expect(movie.state, fetched[id]!.state);
      }
      final movie = movies[1]!;
      expect(movie.runtime, fetched[1]!.runtime);
      expect(movie.file?.id, 4);
      expect(
        movie.images.map((i) => i.instancePath),
        fetched[1]!.images.map((i) => i.instancePath),
      );
    });

    test('tells an empty library from one never fetched', () async {
      final harness = Harness();
      harness.server.movies = [];

      await succeed(harness.library.list());
      final cached = await succeed(harness.library.cachedList());

      expect(cached!.value, isEmpty);
    });

    test('drops what a later list no longer has', () async {
      final harness = Harness();
      await succeed(harness.library.list());
      harness.server.movies.removeWhere((movie) => movie['id'] == 4);

      await succeed(harness.library.list());
      final cached = await succeed(harness.library.cachedList());

      expect(byId(cached!.value).keys, isNot(contains(4)));
      expect(cached.value, hasLength(6));
    });

    test('keeps one movie that was read', () async {
      final harness = Harness();
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await succeed(harness.library.item(movieRef(1)));
      harness.server.requests.clear();

      final cached = await succeed(harness.library.cachedItem(movieRef(1)));

      expect(harness.server.requests, isEmpty);
      expect(cached!.value.ref, movieRef(1));
      expect(cached.value.title, recorded('movie', 1)['title']);
      expect(cached.fetchedAt.isAfter(before), isTrue);
      expect(cached.fetchedAt.isAfter(DateTime.now()), isFalse);
      // One movie is not the library.
      expect(await succeed(harness.library.cachedList()), isNull);
    });

    test('forgets a movie the server no longer has', () async {
      final harness = Harness();
      await succeed(harness.library.list());
      harness.server.movies.removeWhere((movie) => movie['id'] == 4);

      await failureOf(harness.library.item(movieRef(4)));

      expect(await succeed(harness.library.cachedItem(movieRef(4))), isNull);
      final cached = await succeed(harness.library.cachedList());
      expect(cached!.value, hasLength(6));
    });

    test('is left alone by a failed fetch', () async {
      final harness = Harness();
      await succeed(harness.library.list());
      harness.server.down = failedAnswer(const Unreachable());

      await failureOf(harness.library.list());
      await failureOf(harness.library.item(movieRef(1)));

      expect(harness.cache.entries, hasLength(7));
    });
  });

  group('failures', () {
    final reads = <String, Future<ServiceFailure> Function(Harness)>{
      'list': (h) => failureOf(h.library.list()),
      'item': (h) => failureOf(h.library.item(movieRef(1))),
      'files': (h) => failureOf(h.library.files(movieRef(1))),
    };
    for (final MapEntry(key: name, value: read) in reads.entries) {
      for (final failure in <ServiceFailure>[
        const Unreachable(),
        const AuthFailed(),
        const ProxyInterception(),
      ]) {
        test('$name passes on ${failure.runtimeType}', () async {
          final harness = Harness()..server.down = failedAnswer(failure);

          expect(await read(harness), same(failure));
        });
      }

      for (final MapEntry(key: what, value: body) in {
        'broken JSON': '[{"id":',
        'a body of another shape': '"ok"',
      }.entries) {
        test('$name cannot understand $what', () async {
          final harness = Harness()..server.down = textAnswer(body);

          expect(await read(harness), isA<MalformedResponse>());
        });
      }
    }
  });
}
