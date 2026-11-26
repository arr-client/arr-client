// Interactive search and grab for a movie (story 5, scenarios 3 and 4). The
// requests, the mapping of the records and the reading of failures are shared
// Servarr behaviour and are tested in packages/servarr; here is what Radarr
// binds.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import 'library_support.dart';
import 'manage_support.dart';

List<Map<String, Object?>> _recorded() => records(fixture('manage_releases'));

/// A Radarr that finds the recorded releases and takes a grab of [release].
ManageHarness _harness([Map<String, Object?>? release]) {
  final harness = ManageHarness();
  harness.radarr.routes['GET release'] = replyJson(_recorded());
  if (release != null) {
    // The answer as seen of a grab: the two fields in an otherwise empty
    // release.
    harness.radarr.routes['POST release'] = replyJson({
      'guid': release['guid'],
      'indexerId': release['indexerId'],
    });
  }
  return harness;
}

/// The recorded releases, as the module gives them.
Future<List<Release>> _found(ManageHarness harness) =>
    succeed(harness.releases.releases(MediaTarget(movieRef(1))));

void main() {
  test('is offered, and asks nothing by itself', () {
    final harness = ManageHarness();

    expect(
      RadarrModule().capabilitiesFor(
        const ProbeResult(product: 'Radarr', version: '7.0.3.10918'),
        null,
      ),
      contains(CapabilityKind.release),
    );
    harness.releases;
    expect(harness.sent, isEmpty);
  });

  group('releases', () {
    test('searches for the movie alone', () async {
      final harness = _harness();

      await _found(harness);

      final request = harness.server.requests.single;
      expect(asked(request), 'GET release');
      expect(request.query, {
        'movieId': ['1'],
      });
      expect(request.body, isNull);
      // The server asks its indexers while the request is open.
      expect(request.timeout, const Duration(minutes: 2));
    });

    test('lists every release, the rejected ones with their reasons', () async {
      final wire = _recorded();

      final found = await _found(_harness());

      expect(found, hasLength(wire.length));
      for (final (index, release) in found.indexed) {
        final record = wire[index];
        expect(release.guid, record['guid']);
        expect(release.indexerId, record['indexerId']);
        expect(release.title, record['title']);
        expect(release.protocol.name, record['protocol']);
        expect(release.size, record['size']);
        expect(release.score, record['customFormatScore']);
        expect(release.seeders, record['seeders']);
        expect(release.leechers, record['leechers']);
        expect(release.rejections, record['rejections']);
        expect(release.rejections, isNotEmpty);
        // Every field is kept; what a grab needs besides may be added.
        for (final MapEntry(:key, :value) in record.entries) {
          expect(release.rawJson[key], value, reason: key);
        }
      }
    });

    for (final MapEntry(key: name, value: target) in foreignTargets.entries) {
      test('asks nothing for $name', () async {
        final harness = _harness();

        expect(
          await failureOf(harness.releases.releases(target)),
          isA<Validation>(),
        );
        expect(harness.sent, isEmpty);
      });
    }

    test('passes on a failure', () async {
      const failure = ServerError();
      final harness = ManageHarness()
        ..radarr.down = failedAnswer(failure, status: 500);

      expect(
        await failureOf(harness.releases.releases(MediaTarget(movieRef(1)))),
        same(failure),
      );
      expect(harness.sent, ['GET release']);
    });
  });

  group('grab', () {
    // Rejected, but matched to the movie: the server needs nothing more.
    test('names the release by its indexer and guid alone', () async {
      final wire = _recorded()[1];
      expect(wire['downloadAllowed'], isTrue);
      final harness = _harness(wire);
      final release = (await _found(harness))[1];
      harness.server.requests.clear();

      await succeed(harness.releases.grab(release));

      final request = harness.server.requests.single;
      expect(asked(request), 'POST release');
      expect(request.query, isEmpty);
      expect(sentBody(request), {
        'guid': wire['guid'],
        'indexerId': wire['indexerId'],
      });
    });

    // The server could not match it to a movie, so it takes the grab only with
    // the movie that was searched for, as its web UI sends it.
    test('names the searched movie for a release that is not allowed '
        'by itself', () async {
      final wire = records(fixture('manage_releases_unmatched')).single;
      expect(wire['downloadAllowed'], isFalse);
      // Nothing in the record says which movie was searched for.
      expect(wire.keys, isNot(contains('mappedMovieId')));
      expect(wire.keys, isNot(contains('movieId')));
      final harness = ManageHarness();
      harness.radarr.routes['GET release'] = replyJson([wire]);
      harness.radarr.routes['POST release'] = replyJson({
        'guid': wire['guid'],
        'indexerId': wire['indexerId'],
      });
      Future<Release> search(int movie) async => (await succeed(
        harness.releases.releases(MediaTarget(movieRef(movie))),
      )).single;
      final first = await search(1);
      final second = await search(2);
      harness.server.requests.clear();

      // Each release goes with its own search, not with the latest one, and
      // the provider that grabs need not be the one that searched.
      await succeed(harness.releases.grab(first));
      await succeed(harness.releases.grab(second));

      expect(harness.sent, ['POST release', 'POST release']);
      expect(harness.server.requests.map(sentBody), [
        for (final movie in [1, 2])
          {
            'guid': wire['guid'],
            'indexerId': wire['indexerId'],
            'movieId': movie,
          },
      ]);
    });

    for (final (failure, status) in writeFailures) {
      test('passes on ${failure.runtimeType} and is sent once', () async {
        final harness = _harness();
        final release = (await _found(harness)).first;
        harness.server.requests.clear();
        harness.radarr.routes['POST release'] = failedAnswer(
          failure,
          status: status,
        );

        expect(await failureOf(harness.releases.grab(release)), same(failure));
        expect(harness.sent, ['POST release']);
      });
    }

    // The server accepted the request, so it may well be downloading.
    test('cannot tell the outcome of an answer it cannot read', () async {
      final harness = _harness();
      final release = (await _found(harness)).first;
      harness.server.requests.clear();
      harness.radarr.routes['POST release'] = reply('{"guid":');

      expect(
        await failureOf(harness.releases.grab(release)),
        isA<OutcomeUnknown>(),
      );
      expect(harness.sent, ['POST release']);
    });
  });
}
