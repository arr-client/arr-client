// Browsing, searching and titles against recorded answers (spec story 9,
// scenario 2; data-model DiscoveryTitle).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _lists = {
  DiscoveryCategory.trending: ('discover/trending', 'discover_trending'),
  DiscoveryCategory.popularMovies: ('discover/movies', 'discover_movies'),
  DiscoveryCategory.popularSeries: ('discover/tv', 'discover_tv'),
  DiscoveryCategory.upcomingMovies: (
    'discover/movies/upcoming',
    'discover_movies_upcoming',
  ),
  DiscoveryCategory.upcomingSeries: (
    'discover/tv/upcoming',
    'discover_tv_upcoming',
  ),
};

const _film = DiscoveryRef(mediaType: DiscoveryMediaType.movie, tmdbId: 10331);

/// The movies and series of a recorded page.
List<Map<String, Object?>> _titles(
  String name, [
  Product product = Product.seerr,
]) => [
  for (final result in results(name, product))
    if (result['mediaType'] case 'movie' || 'tv') result,
];

int? _year(Object? date) =>
    date is String && date.length >= 4 ? int.parse(date.substring(0, 4)) : null;

void _expectMatches(DiscoveryTitle found, Map<String, Object?> wire) {
  final isMovie = wire['mediaType'] == 'movie';
  expect(found.tmdbId, wire['id']);
  expect(
    found.mediaType,
    isMovie ? DiscoveryMediaType.movie : DiscoveryMediaType.series,
  );
  expect(found.title, wire[isMovie ? 'title' : 'name']);
  expect(found.year, _year(wire[isMovie ? 'releaseDate' : 'firstAirDate']));
  final media = wire['mediaInfo'] as Map<String, Object?>?;
  expect(found.mediaId, media?['id']);
  if (media == null) {
    expect(found.availability, Availability.unknown);
    expect(found.availability4k, Availability.unknown);
  }
}

void main() {
  group('discover', () {
    for (final MapEntry(key: category, value: (path, name)) in _lists.entries) {
      test('lists ${category.name}', () async {
        final http = FakeSeerr()..set('GET api/v1/$path', ok(fixture(name)));

        final page = valueOf(await discovery(http).discover(category));

        expect(http.reads(path).single.query, {
          'page': ['1'],
        });
        final wire = _titles(name);
        expect(page.items, hasLength(wire.length));
        for (final (index, found) in page.items.indexed) {
          _expectMatches(found, wire[index]);
        }
        expect(page.page, 1);
        expect(
          page.hasMore,
          (recorded(name)['page']! as int) <
              (recorded(name)['totalPages']! as int),
        );
        expect(http.writes, isEmpty);
      });
    }

    test('asks for a later page and knows the last', () async {
      final http = FakeSeerr()
        ..set(
          'GET api/v1/discover/movies',
          json({...recorded('discover_movies'), 'page': 3, 'totalPages': 3}),
        );

      final page = valueOf(
        await discovery(http)
            .discover(DiscoveryCategory.popularMovies, page: 3),
      );

      expect(http.reads('discover/movies').single.query, {
        'page': ['3'],
      });
      expect(page.page, 3);
      expect(page.hasMore, isFalse);
    });
  });

  group('search', () {
    // A search and the trending list also name people and collections
    // (server/models/Search.ts). These two are made up.
    test('keeps movies and series only', () async {
      final http = FakeSeerr()
        ..set(
          'GET api/v1/search',
          json({
            ...recorded('search'),
            'results': [
              {
                'id': 1,
                'mediaType': 'person',
                'name': 'A person',
                'knownFor': <Object?>[],
              },
              ...results('search'),
              {'id': 2, 'mediaType': 'collection', 'title': 'A collection'},
            ],
          }),
        );

      final page = valueOf(await discovery(http).search('night'));

      final wire = _titles('search');
      expect(page.items.map((found) => found.tmdbId), [
        for (final result in wire) result['id'],
      ]);
      expect(page.hasMore, isTrue);
    });

    for (final product in Product.values) {
      test('shows what ${product.label} knows of a title', () async {
        final http = FakeSeerr(product: product)
          ..set('GET api/v1/search', ok(fixture('search_requested', product)));

        final page = valueOf(await discovery(http).search('night', page: 2));

        expect(http.reads('search').single.query, {
          'query': ['night'],
          'page': ['2'],
        });
        for (final (index, found) in page.items.indexed) {
          _expectMatches(found, _titles('search_requested', product)[index]);
        }
        final known = page.items.first;
        expect(known.mediaId, isNotNull);
        final status =
            (_titles('search_requested', product).first['mediaInfo']!
                as Map<String, Object?>)['status'];
        expect(
          known.availability,
          status == 2 ? Availability.pending : Availability.processing,
        );
        expect(known.availability4k, Availability.unknown);
      });
    }

    // The client encodes it; a term encoded here would be encoded twice. What
    // goes over the wire is checked in session_test.dart.
    test('hands the term to the client as typed', () async {
      const term = "a+b & c=d !'()* #1? 100% /é:";
      final http = FakeSeerr()..set('GET api/v1/search', ok(fixture('search')));

      valueOf(await discovery(http).search(term));

      expect(http.reads('search').single.query['query'], [term]);
    });

    test('reports a failure', () async {
      final http = FakeSeerr()
        ..set(
          'GET api/v1/search',
          answered(500, '{"message":"Unable to retrieve search results."}'),
        );

      expect(
        failureOf(await discovery(http).search('night')),
        isA<ServerError>(),
      );
    });

    test('reports an answer that is not a page', () async {
      final http = FakeSeerr()..set('GET api/v1/search', ok('{"results":3}'));

      expect(
        failureOf(await discovery(http).search('night')),
        isA<MalformedResponse>(),
      );
    });
  });

  group('detail', () {
    FakeSeerr server(
      String path,
      String name, [
      Product product = Product.seerr,
    ]) =>
        FakeSeerr(product: product)
          ..set('GET api/v1/$path', ok(fixture(name, product)));

    Future<DiscoveryTitle> movie(FakeSeerr http, int id) async => valueOf(
      await discovery(
        http,
      ).detail(DiscoveryRef(mediaType: DiscoveryMediaType.movie, tmdbId: id)),
    );

    test('of a title the server does not know', () async {
      final found = await movie(server('movie/19', 'movie_unknown'), 19);
      final wire = recorded('movie_unknown');

      expect(found.tmdbId, 19);
      expect(found.title, wire['title']);
      expect(found.year, _year(wire['releaseDate']));
      expect(found.mediaId, isNull);
      expect(found.availability, Availability.unknown);
      expect(found.requestStatus, isNull);
      expect(found.requestStatus4k, isNull);
    });

    // Only a title's own page carries its requests.
    for (final product in Product.values) {
      test('of a requested movie on ${product.label}', () async {
        final found = await movie(
          server('movie/10331', 'movie_requested', product),
          10331,
        );
        final media =
            recorded('movie_requested', product)['mediaInfo']!
                as Map<String, Object?>;

        expect(found.mediaId, media['id']);
        expect(found.requestStatus, isNotNull);
        expect(found.requestStatus4k, isNull);
      });
    }

    test('of a series', () async {
      final found = valueOf(
        await discovery(server('tv/1100', 'tv')).detail(
          const DiscoveryRef(
            mediaType: DiscoveryMediaType.series,
            tmdbId: 1100,
          ),
        ),
      );
      final wire = recorded('tv');

      expect(found.mediaType, DiscoveryMediaType.series);
      expect(found.title, wire['name']);
      expect(found.year, _year(wire['firstAirDate']));
      // Matches the series against library search results.
      expect(found.tvdbId, 75760);
      expect(found.requestStatus, RequestStatus.pending);
    });

    // A failed 4K request leaves the standard variant untouched.
    test('keeps the variants apart', () async {
      final found = await movie(server('movie/653', 'movie_4k'), 653);

      expect(found.availability, Availability.unknown);
      expect(found.availability4k, Availability.processing);
      expect(found.requestStatus, isNull);
      expect(found.requestStatus4k, RequestStatus.failed);
    });

    test('takes the newest request of a variant', () async {
      final wire = recorded('movie_requested');
      final media = wire['mediaInfo']! as Map<String, Object?>;
      final request =
          (media['requests']! as List<Object?>).first! as Map<String, Object?>;
      final http = FakeSeerr()
        ..set(
          'GET api/v1/movie/10331',
          json({
            ...wire,
            'mediaInfo': {
              ...media,
              // In no particular order.
              'requests': [
                {...request, 'id': 31, 'status': 1},
                {...request, 'id': 30, 'status': 3},
                {...request, 'id': 32, 'status': 2, 'is4k': true},
              ],
            },
          }),
        );

      final found = await movie(http, 10331);

      expect(found.requestStatus, RequestStatus.pending);
      expect(found.requestStatus4k, RequestStatus.approved);
    });

    test('reports a title that does not exist', () async {
      final failure = failureOf(
        await discovery(FakeSeerr()).detail(
          const DiscoveryRef(mediaType: DiscoveryMediaType.movie, tmdbId: 1),
        ),
      );

      expect(failure, isA<NotFound>());
    });
  });

  // The same numbers from 6 on mean different things (data-model
  // DiscoveryTitle).
  group('availability numbers', () {
    const unknown = Availability.unknown;
    const common = [
      unknown, // 0
      unknown, // 1
      Availability.pending,
      Availability.processing,
      Availability.partial,
      Availability.available, // 5
    ];
    const blocklisted = Availability.blocklisted;
    const deleted = Availability.deleted;
    const current = [...common, blocklisted, deleted, unknown];
    final cases = <(Product, String), List<Availability>>{
      (Product.seerr, '3.5.2'): current,
      (Product.seerr, '3.0.0'): current,
      (Product.jellyseerr, '2.7.3'): current,
      // 7 does not exist yet.
      (Product.jellyseerr, '2.0.0'): [...common, blocklisted],
      // Overseerr has no blocklist.
      (Product.overseerr, '1.35.0'): [...common, deleted, unknown, unknown],
      (Product.overseerr, '1.34.0'): [...common, unknown, unknown],
    };

    for (final MapEntry(key: (product, version), value: expected)
        in cases.entries) {
      test('of ${product.label} $version', () async {
        final wire = recorded('movie_requested', product);
        final media = wire['mediaInfo']! as Map<String, Object?>;
        for (final (number, availability) in expected.indexed) {
          final http = FakeSeerr(product: product)
            ..set(
              'GET api/v1/movie/10331',
              json({
                ...wire,
                'mediaInfo': {...media, 'status': 1, 'status4k': number},
              }),
            )
            ..set(
              'GET api/v1/search',
              json({
                'page': 1,
                'totalPages': 1,
                'totalResults': 1,
                'results': [
                  {
                    ..._titles('search_requested', product).first,
                    'mediaInfo': {...media, 'status': number, 'status4k': 1},
                  },
                ],
              }),
            );
          final provider = discovery(http, version: version);

          final detail = valueOf(await provider.detail(_film));
          final found = valueOf(await provider.search('night')).items.single;

          expect(detail.availability4k, availability, reason: '4K $number');
          expect(detail.availability, unknown);
          expect(found.availability, availability, reason: '$number');
          expect(found.availability4k, unknown);
        }
      });
    }

    // A deleted title can be asked for again; a blocklisted one cannot.
    test('leaves a title Overseerr deleted requestable', () async {
      final wire = recorded('movie_requested', Product.overseerr);
      final http = FakeSeerr(product: Product.overseerr)
        ..set(
          'GET api/v1/movie/10331',
          json({
            ...wire,
            'mediaInfo': {
              ...wire['mediaInfo']! as Map<String, Object?>,
              'status': 6,
            },
          }),
        );

      final found = valueOf(await discovery(http).detail(_film));

      expect(found.availability, Availability.deleted);
      expect(found.availability.blocksRequest, isFalse);
    });

    test('blocks a blocklisted title in both variants', () async {
      final http = FakeSeerr()
        ..set('GET api/v1/movie/961', ok(fixture('movie_blocklisted')));

      final found = valueOf(
        await discovery(http).detail(
          const DiscoveryRef(mediaType: DiscoveryMediaType.movie, tmdbId: 961),
        ),
      );

      expect(found.availability.blocksRequest, isTrue);
      expect(found.availability4k.blocksRequest, isTrue);
    });
  });
}
