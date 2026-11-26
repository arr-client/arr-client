// LookupProvider.lookup against recorded answers (spec story 3).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import '../allow_list.dart';
import 'library_support.dart';
import 'lookup_support.dart';

// The shapes sanitizing took away: a title outside the library has a proxy
// address that no listed read serves, with the public one beside it.
const _proxied =
    '/MediaCoverProxy/'
    '575804ada86e356966a7ec8691cee1d37a6742a8aee910f63dd2c87bd06d63cd'
    '/poster.jpg';
const _public = 'https://image.tmdb.org/t/p/original/poster.jpg';

Future<List<AddCandidate>> _lookup(LookupHarness harness, String term) =>
    succeed(harness.lookup.lookup(term));

/// The one result of lookup_new, with [changes] applied.
Future<AddCandidate> _changed(
  Map<String, Object?> changes, {
  Set<String> without = const {},
}) async {
  final harness = LookupHarness();
  harness.radarr.found['x'] = [
    {...records(fixture('lookup_new')).single, ...changes}
      ..removeWhere((field, _) => without.contains(field)),
  ];
  return (await _lookup(harness, 'x')).single;
}

/// [path] of an image must be a read the allow-list has.
bool _permitted(String path) {
  final uri = Uri.parse(path);
  return allowList.permits(
    ServiceRequest(HttpMethod.get, uri.path, query: uri.queryParametersAll),
  );
}

void main() {
  test('adds movies', () {
    expect(LookupHarness().lookup.itemKinds, {MediaKind.movie});
  });

  test('is a capability the module offers', () {
    final offered = RadarrModule().capabilitiesFor(
      const ProbeResult(
        product: 'Radarr',
        version: '7.0.3.10918',
        newerThanTested: false,
      ),
      null,
    );

    expect(offered, contains(CapabilityKind.lookup));
  });

  group('lookup', () {
    test('asks once, with the term as typed, and only reads', () async {
      const term = "bunny & friends: the 'sequel' (2)";
      final harness = LookupHarness();

      await _lookup(harness, term);

      final request = harness.radarr.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, lookupPath);
      // Encoding it is the client's work.
      expect(request.query, {
        'term': [term],
      });
      expect(request.body, isNull);
    });

    test('finds nothing for a blank term, without asking', () async {
      for (final term in ['', '   ']) {
        final harness = LookupHarness();

        expect(await _lookup(harness, term), isEmpty);
        expect(harness.radarr.requests, isEmpty);
      }
    });

    test('is empty when the server finds nothing', () async {
      expect(await _lookup(LookupHarness(), 'zzqx'), isEmpty);
    });

    test('gives every result in the order of the server', () async {
      final wire = records(fixture('lookup_term'));

      final results = await _lookup(LookupHarness(), 'big buck bunny');

      expect(
        results.map((r) => r.externalIds.tmdbId),
        wire.map((record) => record['tmdbId']),
      );
      expect(results.map((r) => r.kind).toSet(), {MediaKind.movie});
    });

    test('maps what a result shows', () async {
      final wire = records(fixture('lookup_new')).single;

      final result = (await _lookup(LookupHarness(), 'bunny')).single;

      expect(result.title, wire['title']);
      expect(result.year, 2008);
      expect(result.overview, wire['overview']);
      expect(result.parentTitle, isNull);
      expect(result.externalIds.tmdbId, bunnyTmdbId);
      expect(result.externalIds.imdbId, 'tt1254207');
      expect(result.externalIds.tvdbId, isNull);
      expect(result.externalIds.musicBrainzId, isNull);
      expect(result.externalIds.foreignId, isNull);
    });

    test('leaves out what the server does not know', () async {
      final results = await _lookup(LookupHarness(), 'big buck bunny');

      // Recorded with year 0, no pictures and no IMDb id.
      final unknown = results.last;
      expect(unknown.year, isNull);
      expect(unknown.images, isEmpty);
      expect(unknown.externalIds.imdbId, isNull);
      expect(unknown.externalIds.tmdbId, 1627969);
    });

    test('takes empty and zero identifiers as none', () async {
      final result = await _changed({'tmdbId': 0, 'imdbId': ''});

      expect(result.externalIds.tmdbId, isNull);
      expect(result.externalIds.imdbId, isNull);
    });

    test('does without the optional fields', () async {
      final result = await _changed(
        const {},
        without: {'year', 'overview', 'images', 'imdbId'},
      );

      expect(result.year, isNull);
      expect(result.overview, isNull);
      expect(result.images, isEmpty);
      expect(result.externalIds.imdbId, isNull);
      expect(result.existingRefs, isEmpty);
    });

    test('ignores fields and values it does not know', () async {
      final result = await _changed({
        'someFutureField': {'a': 1},
        'status': 'someFutureStatus',
      });

      expect(result.externalIds.tmdbId, bunnyTmdbId);
      expect(result.sourceByInstance[instanceId]!['someFutureField'], {'a': 1});
    });

    test('marks what the instance already has', () async {
      final results = await _lookup(LookupHarness(), 'big buck bunny');

      expect(results.first.existingRefs, [movieRef(1)]);
      expect(results.last.existingRefs, isEmpty);
    });

    test('takes an id of zero, like none, as not in the library', () async {
      final result = await _changed({'id': 0});

      expect(result.existingRefs, isEmpty);
    });

    test('keeps the record of the instance to post back', () async {
      final wire = records(fixture('lookup_term'));

      final results = await _lookup(LookupHarness(), 'big buck bunny');

      for (final (index, result) in results.indexed) {
        expect(result.sourceByInstance, {instanceId: wire[index]});
      }
    });

    test('leaves the cache of the library alone', () async {
      final harness = LookupHarness();

      await _lookup(harness, 'big buck bunny');

      expect(harness.cache.entries, isEmpty);
      expect(await harness.cache.read(MediaKind.movie), isNull);
    });
  });

  group('artwork', () {
    test('of a movie in the library is read from the instance', () async {
      final wire = records(records(fixture('lookup_term')).first['images']);

      final result = (await _lookup(LookupHarness(), 'big buck bunny')).first;

      expect(result.images.map((i) => i.type), [
        MediaImageType.poster,
        MediaImageType.fanart,
      ]);
      expect(result.images.map((i) => i.instancePath), [
        'api/v3/mediacover/1/poster.jpg',
        'api/v3/mediacover/1/fanart.jpg',
      ]);
      expect(
        result.images.map((i) => i.remoteUrl),
        wire.map((image) => Uri.parse(image['remoteUrl']! as String)),
      );
      for (final image in result.images) {
        expect(_permitted(image.instancePath!), isTrue);
      }
    });

    // The proxy address is behind no listed read.
    for (final (name, url) in [
      ('at the root', _proxied),
      ('under a URL base', '/radarr$_proxied'),
    ]) {
      test('outside the library is public, with a proxy $name', () async {
        final result = await _changed({
          'images': [
            {'coverType': 'poster', 'url': url, 'remoteUrl': _public},
          ],
        });

        final image = result.images.single;
        expect(image.type, MediaImageType.poster);
        expect(image.instancePath, isNull);
        expect(image.remoteUrl, Uri.parse(_public));
      });
    }

    test('with only a proxy address is left out', () async {
      final result = await _changed({
        'images': [
          {'coverType': 'poster', 'url': _proxied},
        ],
      });

      expect(result.images, isEmpty);
    });
  });

  group('failures', () {
    for (final failure in const [
      Unreachable(),
      AuthFailed(),
      ServerError(statusCode: 503),
    ]) {
      test('passes on ${failure.runtimeType} and asks once', () async {
        final harness = LookupHarness()..radarr.down = failedAnswer(failure);

        expect(await failureOf(harness.lookup.lookup('bunny')), same(failure));
        expect(harness.radarr.requests, hasLength(1));
      });
    }

    for (final (name, body) in [
      ('text that is not JSON', 'no'),
      ('an object', '{}'),
      ('a list of numbers', '[1]'),
      ('a record without a title', '[{"tmdbId": 10378}]'),
    ]) {
      test('cannot understand $name', () async {
        final harness = LookupHarness();
        harness.radarr.answers[lookupPath] = textAnswer(body);

        expect(
          await failureOf(harness.lookup.lookup('bunny')),
          isA<MalformedResponse>(),
        );
      });
    }
  });
}
