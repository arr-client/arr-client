// Making and managing requests against recorded answers (spec story 9,
// scenarios 3 and 4).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _statuses = {
  1: RequestStatus.pending,
  2: RequestStatus.approved,
  3: RequestStatus.declined,
  4: RequestStatus.failed,
  5: RequestStatus.completed,
};

const _availability = {
  1: Availability.unknown,
  2: Availability.pending,
  3: Availability.processing,
  4: Availability.partial,
  5: Availability.available,
};

typedef _Action = Future<Result<void, ServiceFailure>> Function(
  RequestProvider provider,
);

void _expectMatches(MediaRequest request, Map<String, Object?> wire) {
  final media = wire['media']! as Map<String, Object?>;
  final user = wire['requestedBy']! as Map<String, Object?>;
  final is4k = wire['is4k']! as bool;
  expect(request.id, wire['id']);
  expect(
    request.titleRef,
    DiscoveryRef(
      mediaType: media['mediaType'] == 'movie'
          ? DiscoveryMediaType.movie
          : DiscoveryMediaType.series,
      tmdbId: media['tmdbId']! as int,
    ),
  );
  expect(request.status, _statuses[wire['status']]);
  expect(
    request.availability,
    _availability[media[is4k ? 'status4k' : 'status']],
  );
  expect(request.is4k, is4k);
  expect(request.requestedBy.id, user['id']);
  expect(request.requestedBy.name, user['displayName']);
  // The answer to a new movie request has no `seasons` at all.
  expect(request.seasons, [
    for (final season in wire['seasons'] as List<Object?>? ?? const [])
      (season! as Map<String, Object?>)['seasonNumber'],
  ]);
}

void main() {
  group('request', () {
    FakeSeerr server(String name) =>
        FakeSeerr()..set('POST api/v1/request', answered(201, fixture(name)));

    // `mediaId` on the wire is the TMDB id, not the server's media record.
    test('asks for a movie by its TMDB id', () async {
      final http = server('request_created_movie');

      final made = valueOf(
        await requests(http)
            .request(title(tmdbId: 10331, mediaId: 9), is4k: false),
      );

      expect(sent(http.writes.single), {
        'mediaType': 'movie',
        'mediaId': 10331,
        'is4k': false,
      });
      _expectMatches(made, recorded('request_created_movie'));
    });

    test('asks for chosen seasons in 4K', () async {
      final http = server('request_created_tv');

      final made = valueOf(
        await requests(http).request(
          title(tmdbId: 1100, type: DiscoveryMediaType.series, mediaId: null),
          is4k: true,
          seasons: [1, 2],
        ),
      );

      final body = sent(http.writes.single);
      expect(body['mediaType'], 'tv');
      expect(body['mediaId'], 1100);
      expect(body['is4k'], true);
      expect(body['seasons'], [1, 2]);
      expect(made.seasons, [1, 2]);
    });

    // The server fails on a series without them.
    test('sends nothing for a series without a season', () async {
      final http = server('request_created_tv');

      final result = await requests(http).request(
        title(tmdbId: 1100, type: DiscoveryMediaType.series),
        is4k: false,
      );

      expect(failureOf(result), isA<Validation>());
      expect(http.writes, isEmpty);
    });

    Future<ServiceFailure> refused(Answer answer) async {
      final http = FakeSeerr()..set('POST api/v1/request', answer);
      final failure = failureOf(
        await requests(http).request(title(), is4k: false),
      );
      expect(http.writes, hasLength(1));
      return failure;
    }

    test('reports a duplicate', () async {
      expect(
        await refused(answered(409, fixture('request_duplicate'))),
        isA<Conflict>(),
      );
    });

    // The reason is only in the server's message.
    for (final name in [
      'request_over_quota',
      'request_no_4k',
      'request_blocklisted',
    ]) {
      test('reports $name', () async {
        expect(
          await refused(answered(403, fixture(name))),
          anyOf(isA<Forbidden>(), isA<Validation>()),
        );
      });
    }

    // A success status that made nothing.
    test('does not take "no seasons available" for a request', () async {
      expect(
        await refused(
          json({'message': 'No seasons available to request'}, status: 202),
        ),
        anyOf(isA<Conflict>(), isA<Validation>()),
      );
    });

    test('reports an unknown outcome and does not repeat', () async {
      expect(
        await refused(unsent(const OutcomeUnknown())),
        isA<OutcomeUnknown>(),
      );
    });
  });

  group('list', () {
    for (final product in Product.values) {
      test('reads the requests of ${product.label}', () async {
        final http = FakeSeerr(product: product)
          ..set('GET api/v1/request', ok(fixture('requests', product)));

        final page = valueOf(await requests(http).list());

        final query = http.reads('request').single.query;
        expect(query['skip'], ['0']);
        expect(int.parse(query['take']!.single), greaterThan(0));
        final wire = results('requests', product);
        expect(page.items, hasLength(wire.length));
        for (final (index, request) in page.items.indexed) {
          _expectMatches(request, wire[index]);
        }
        expect(page.page, 1);
        expect(page.hasMore, isFalse);
        expect(http.writes, isEmpty);
      });
    }

    test('skips the earlier pages', () async {
      final http = FakeSeerr()
        ..set(
          'GET api/v1/request',
          json({
            ...recorded('requests'),
            'pageInfo': {'pages': 4, 'pageSize': 20, 'results': 70, 'page': 3},
          }),
        );

      final page = valueOf(await requests(http).list(page: 3));

      final query = http.reads('request').single.query;
      expect(
        int.parse(query['skip']!.single),
        2 * int.parse(query['take']!.single),
      );
      expect(page.page, 3);
      expect(page.hasMore, isTrue);
    });

    test('reads every status, also one it does not know', () async {
      final first = results('requests').first;
      final http = FakeSeerr()
        ..set(
          'GET api/v1/request',
          json({
            ...recorded('requests'),
            'results': [
              for (final status in [1, 2, 3, 4, 5, 99])
                {...first, 'status': status},
            ],
          }),
        );

      final page = valueOf(await requests(http).list());

      expect(page.items.map((request) => request.status), [
        ..._statuses.values,
        RequestStatus.unknown,
      ]);
    });
  });

  group('manage', () {
    final actions = <String, (String, String?, _Action)>{
      'approve': (
        'POST api/v1/request/9/approve',
        'approve',
        (provider) => provider.approve(9),
      ),
      'decline': (
        'POST api/v1/request/9/decline',
        'decline',
        (provider) => provider.decline(9),
      ),
      'retry': (
        'POST api/v1/request/9/retry',
        'retry',
        (provider) => provider.retry(9),
      ),
      'delete': (
        'DELETE api/v1/request/9',
        null,
        (provider) => provider.delete(9),
      ),
    };

    for (final MapEntry(key: name, value: (route, body, run))
        in actions.entries) {
      group(name, () {
        test('sends one request without a body', () async {
          final http = FakeSeerr()
            ..set(route, body == null ? answered(204, '') : ok(fixture(body)));

          expectOk(await run(requests(http)));

          final write = http.writes.single;
          expect('${write.method.name.toUpperCase()} ${write.path}', route);
          expect(write.body, isNull);
        });

        test('reports a request that is gone', () async {
          final http = FakeSeerr()
            ..set(route, answered(404, fixture('delete_missing')));

          expect(failureOf<void>(await run(requests(http))), isA<NotFound>());
          expect(http.writes, hasLength(1));
        });

        test('reports a missing permission', () async {
          final http = FakeSeerr()..set(route, answered(403, noPermission));

          expect(failureOf<void>(await run(requests(http))), isA<Forbidden>());
          expect(http.writes, hasLength(1));
        });
      });
    }

    // Seerr only; its predecessors answer 200.
    test('reports a request that is no longer pending', () async {
      final http = FakeSeerr()
        ..set(
          'POST api/v1/request/9/approve',
          answered(409, fixture('approve_again')),
        );

      expect(failureOf<void>(await requests(http).approve(9)), isA<Conflict>());
    });

    // A 401 about one request, not about the identity.
    test('reports a refused delete as forbidden', () async {
      final http = FakeSeerr()
        ..set(
          'DELETE api/v1/request/9',
          answered(401, fixture('delete_refused')),
        );

      expect(failureOf<void>(await requests(http).delete(9)), isA<Forbidden>());
    });
  });
}
