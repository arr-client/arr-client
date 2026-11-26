// Interactive search, `GET release`, and grab, `POST release` (story 5,
// scenarios 3 and 4). The server grabs by the indexer's id and the release's
// guid, which it holds from the search for a limited time.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'manage_support.dart';
import 'support.dart';

/// The searches each service's allow-list permits, and their recordings.
final _searches = [
  (radarr, <String, int>{'movieId': 1}, 'manage_releases'),
  (sonarr, <String, int>{'episodeId': 1}, 'manage_releases'),
  (
    sonarr,
    <String, int>{'seriesId': 1, 'seasonNumber': 1},
    'manage_releases_season',
  ),
];

Map<String, int> _target(Service service) =>
    service == radarr ? const {'movieId': 1} : const {'episodeId': 1};

Future<List<Release>> _releases(
  Service service,
  Object? body, [
  Map<String, int>? target,
]) => value(
  service
      .client(routes({'GET release': Reply.json(body)}))
      .releases(target ?? _target(service)),
);

/// The first recorded release, with [changes] and [without] those fields.
Future<Release> _release(
  Service service, [
  Map<String, Object?> changes = const {},
  List<String> without = const [],
]) async {
  final record = service.list('manage_releases').first
    ..addAll(changes)
    ..removeWhere((key, _) => without.contains(key));
  return (await _releases(service, [record])).single;
}

const _picked = Release(
  guid: 'http://redacted.invalid/9',
  indexerId: 2,
  indexer: 'Example',
  title: 'Some.Release-GRP',
  protocol: DownloadProtocol.torrent,
  size: 1,
  ageHours: 1,
  rawJson: {
    'guid': 'http://redacted.invalid/9',
    'indexerId': 2,
    'downloadUrl': 'redacted',
  },
);

void main() {
  for (final (service, target, fixture) in _searches) {
    group('${service.name} search by ${target.keys.join(' and ')}', () {
      test('asks for the releases of the target alone', () async {
        final server = routes({
          'GET release': Reply.json(service.fixture(fixture)),
        });

        await value(service.client(server).releases(target));

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/release');
        expect(request.query, {
          for (final MapEntry(:key, :value) in target.entries) key: ['$value'],
        });
        expect(request.body, isNull);
        // The server asks its indexers while the request is open.
        expect(request.timeout, const Duration(minutes: 2));
      });

      test('maps every release in the server\'s order', () async {
        final records = service.list(fixture);

        final releases = await _releases(
          service,
          service.fixture(fixture),
          target,
        );

        expect(releases, hasLength(records.length));
        for (final (index, release) in releases.indexed) {
          final record = records[index];
          final quality =
              (record['quality']! as JsonObject)['quality']! as JsonObject;
          expect(release.guid, record['guid']);
          expect(release.indexerId, record['indexerId']);
          expect(release.indexer, record['indexer']);
          expect(release.title, record['title']);
          expect(release.protocol.name, record['protocol']);
          expect(release.size, record['size']);
          expect(release.ageHours, record['ageHours']);
          expect(release.quality?.id, quality['id']);
          expect(release.quality?.name, quality['name']);
          expect(release.score, record['customFormatScore']);
          expect(release.seeders, record['seeders']);
          expect(release.leechers, record['leechers']);
          expect(release.rejections, record['rejections']);
          expect([
            for (final language in release.languages)
              {'id': language.id, 'name': language.name},
          ], record['languages']);
          expect(release.rawJson, record);
        }
      });
    });
  }

  for (final service in services) {
    group('${service.name} releases', () {
      test('keeps rejected releases, with their reasons', () async {
        final releases = await _releases(
          service,
          service.fixture('manage_releases'),
        );

        expect(releases.any((release) => release.rejections.isEmpty), isTrue);
        expect(
          releases.any((release) => release.rejections.isNotEmpty),
          isTrue,
        );
      });

      test('has no seeders or leechers for Usenet', () async {
        final releases = await _releases(
          service,
          service.fixture('manage_releases'),
        );

        final usenet = releases.where(
          (release) => release.protocol == DownloadProtocol.usenet,
        );
        expect(usenet, isNotEmpty);
        for (final release in usenet) {
          expect(release.seeders, isNull);
          expect(release.leechers, isNull);
        }
        // No seeders at all is a number, not the lack of one.
        expect(releases.any((release) => release.seeders == 0), isTrue);
      });

      test('reads a custom format score', () async {
        final releases = await _releases(
          service,
          service.fixture('manage_releases'),
        );

        expect(releases.map((release) => release.score), contains(25));
      });

      test('reads a protocol it does not know as unknown', () async {
        final release = await _release(service, {'protocol': 'carrierPigeon'});

        expect(release.protocol, DownloadProtocol.unknown);
      });

      test('lists a release that says little', () async {
        final release = await _release(service, const {}, [
          'quality',
          'languages',
          'customFormatScore',
          'seeders',
          'leechers',
          'rejections',
        ]);

        expect(release.quality, isNull);
        expect(release.languages, isEmpty);
        expect(release.score, 0);
        expect(release.seeders, isNull);
        expect(release.leechers, isNull);
        expect(release.rejections, isEmpty);
      });

      test('finds nothing', () async {
        expect(await _releases(service, <Object?>[]), isEmpty);
      });

      test('asks nothing without a target', () async {
        final server = routes({'GET release': Reply.json(<Object?>[])});

        expect(
          await failure(service.client(server).releases(const {})),
          isA<Validation>(),
        );
        expect(server.requests, isEmpty);
      });

      // Without both a release cannot be grabbed.
      for (final field in ['guid', 'indexerId']) {
        test('cannot understand a release without $field', () async {
          final record = service.list('manage_releases').first..remove(field);
          final server = routes({
            'GET release': Reply.json([record]),
          });

          expect(
            await failure(service.client(server).releases(_target(service))),
            isA<MalformedResponse>(),
          );
        });
      }
    });

    group('${service.name} grab', () {
      test('names the release by its indexer and guid alone', () async {
        // The answer as seen: the two fields in an otherwise empty release.
        final server = routes({
          'POST release': Reply.json({'guid': _picked.guid, 'indexerId': 2}),
        });

        await value(service.client(server).grab(_picked));

        final request = server.requests.single;
        expect(request.method, HttpMethod.post);
        expect(request.path, 'api/v3/release');
        expect(request.query, isEmpty);
        expect(sentBody(request), {'guid': _picked.guid, 'indexerId': 2});
      });

      test('grabs a release the server would not grab itself', () async {
        final releases = await _releases(
          service,
          service.fixture('manage_releases'),
        );
        final rejected = releases.firstWhere(
          (release) => release.rejections.isNotEmpty,
        );
        final server = routes({'POST release': Reply.json(rejected.rawJson)});

        await value(service.client(server).grab(rejected));

        expect(sentBody(server.requests.single), {
          'guid': rejected.guid,
          'indexerId': rejected.indexerId,
        });
      });

      for (final (name, reply, expected) in [
        (
          'a release the server no longer holds',
          refusal(
            404,
            "Couldn't find requested release in cache, try searching again",
          ),
          isA<NotFound>(),
        ),
        (
          'a release the server cannot match',
          // Radarr's message; Sonarr names series and episodes.
          refusal(
            404,
            'Unable to find matching movie, will need to be manually provided',
          ),
          isA<NotFound>(),
        ),
        (
          'a missing download client',
          refusal(500, "Usenet Download client isn't configured yet"),
          isA<ServerError>(),
        ),
        // Written from the server's source.
        (
          'an indexer that did not give the release',
          refusal(409, 'Getting release from indexer failed'),
          isA<Conflict>(),
        ),
      ]) {
        test('reports $name and is sent once', () async {
          final server = routes({'POST release': reply});

          expect(await failure(service.client(server).grab(_picked)), expected);
          expect(server.requests, hasLength(1));
        });
      }
    });
  }

  group('a failed search', () {
    final failures = <String, (Answer, Type)>{
      ...transportFailures,
      // As recorded for a movie or episode that does not exist.
      'an unknown item': (
        refusal(500, 'Movie with ID 999 does not exist'),
        ServerError,
      ),
      'JSON that breaks off': (
        const Reply(200, '[{"guid":'),
        MalformedResponse,
      ),
      'JSON of another shape': (const Reply(200, '{}'), MalformedResponse),
    };

    for (final MapEntry(key: cause, value: (answer, expected))
        in failures.entries) {
      test('reports $cause', () async {
        final server = FakeServer.always(answer);

        final result = await failure(
          radarr.client(server).releases(const {'movieId': 1}),
        );

        expect(result.runtimeType, expected);
        // A read may be retried once (module contract, rule 5).
        expect(server.requests.length, inInclusiveRange(1, 2));
      });
    }
  });

  group('a failed grab', () {
    final failures = <String, (Answer, Type)>{
      ...writeFailures,
      // The server accepted these, so it may well be downloading.
      'an answer that breaks off': (
        const Reply(200, '{"guid":'),
        OutcomeUnknown,
      ),
      'an answer without a release': (const Reply(200, '[]'), OutcomeUnknown),
    };

    for (final MapEntry(key: cause, value: (answer, expected))
        in failures.entries) {
      test('reports $cause and is sent once', () async {
        final server = FakeServer.always(answer);

        final result = await failure(radarr.client(server).grab(_picked));

        expect(result.runtimeType, expected);
        expect(server.requests, hasLength(1));
      });
    }
  });
}
