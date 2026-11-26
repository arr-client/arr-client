// Searching for series to add.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarr/sonarr_module.dart';

import '../allow_list.dart';
import 'support.dart';

const _term = FakeSonarr.searchTerm;

// Results of the recorded search, by TVDB id.
const _notHeld = 79257;
const _held = 318408;
const _noTmdbId = 83779;
const _bare = 460222;

// As long as the recorded server's: the SHA-256 of the cover's source.
const _hash =
    'd7a26be71c9e0a1a0310f189680b9e8f941d7c023158b81453f1a588bdf0d6d3';

Future<Map<int, AddCandidate>> _search(Harness harness) async => {
  for (final candidate in await ok(harness.lookup.lookup(_term)))
    candidate.externalIds.tvdbId!: candidate,
};

Map<String, Object?> _raw(Harness harness, int tvdbId) =>
    harness.server.lookupResults.singleWhere((r) => r['tvdbId'] == tvdbId);

/// The only image of a result whose record has [image] alone.
Future<List<MediaImage>> _imagesOf(Map<String, Object?> image) async {
  final harness = Harness();
  _raw(harness, _notHeld)['images'] = [image];
  return (await _search(harness))[_notHeld]!.images;
}

void main() {
  test('Sonarr looks up and adds series', () {
    expect(Harness().lookup.itemKinds, {MediaKind.series});
    expect(
      SonarrModule().capabilitiesFor(
        const ProbeResult(
          product: 'Sonarr',
          version: '4.0.20.3014',
          newerThanTested: false,
        ),
        null,
      ),
      contains(CapabilityKind.lookup),
    );
  });

  group('lookup', () {
    test('asks the server once for the term', () async {
      final harness = Harness();

      await ok(harness.lookup.lookup(_term));

      final request = harness.server.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/series/lookup');
      expect(request.query, {
        'term': [_term],
      });
    });

    test('leaves the encoding of the term to the client', () async {
      final harness = Harness();
      const term = "Tom & Jerry's #1: 50% (Again)?";

      expect(await ok(harness.lookup.lookup(term)), isEmpty);

      expect(harness.server.requests.single.query['term'], [term]);
    });

    // The server has nothing to search for, and the allow-list refuses it.
    for (final term in ['', '   ']) {
      test('finds nothing for "$term" without asking', () async {
        final harness = Harness();

        expect(await ok(harness.lookup.lookup(term)), isEmpty);

        expect(harness.server.requests, isEmpty);
      });
    }

    test('every result, in the order of the server', () async {
      final candidates = await ok(Harness().lookup.lookup(_term));

      expect(candidates.map((c) => c.externalIds.tvdbId), [
        _notHeld,
        _noTmdbId,
        _held,
        _bare,
      ]);
      expect(candidates.map((c) => c.kind), everyElement(MediaKind.series));
    });

    test('maps the fields of a result', () async {
      final harness = Harness();
      final raw = _raw(harness, _notHeld);

      final candidate = (await _search(harness))[_notHeld]!;

      expect(candidate.title, raw['title']);
      expect(candidate.year, 2006);
      expect(candidate.overview, raw['overview']);
      expect(candidate.externalIds.tmdbId, 1044);
      expect(candidate.externalIds.imdbId, 'tt0795176');
      expect(candidate.parentTitle, isNull);
    });

    test('takes zero and what is left out as unknown', () async {
      final candidates = await _search(Harness());

      expect(candidates[_noTmdbId]!.externalIds.tmdbId, isNull);
      final bare = candidates[_bare]!;
      expect(bare.year, isNull);
      expect(bare.externalIds.tmdbId, isNull);
      expect(bare.externalIds.imdbId, isNull);
      expect(bare.images, isEmpty);
    });

    test('marks a series that this instance has', () async {
      final candidates = await _search(Harness());

      expect(candidates[_held]!.existingRefs, [seriesRef(1)]);
      for (final tvdbId in [_notHeld, _noTmdbId, _bare]) {
        expect(candidates[tvdbId]!.existingRefs, isEmpty);
      }
    });

    test('keeps each record as received, to post it back', () async {
      final harness = Harness();
      _raw(harness, _notHeld)['somethingNew'] = {'a': 1};

      final candidates = await _search(harness);

      for (final MapEntry(key: tvdbId, value: candidate)
          in candidates.entries) {
        expect(candidate.sourceByInstance, {instanceId: _raw(harness, tvdbId)});
      }
    });

    test('does not put results into the library cache', () async {
      final harness = Harness();

      await ok(harness.lookup.lookup(_term));

      expect(await harness.cache.read(MediaKind.series), isNull);
      expect(await harness.cache.entry(MediaKind.series, 1), isNull);
    });

    test('a search that finds nothing is empty', () async {
      expect(await ok(Harness().lookup.lookup('zzqqxx')), isEmpty);
    });
  });

  group('artwork', () {
    // No listed request reads the server's proxy of a cover.
    for (final base in ['', '/sonarr']) {
      test('of a series not held is read from its source, '
          'under "$base"', () async {
        final images = await _imagesOf({
          'coverType': 'poster',
          'url': '$base/MediaCoverProxy/$_hash/79257-6.jpg',
          'remoteUrl': 'https://artworks.example/posters/79257-6.jpg',
        });

        final image = images.single;
        expect(image.type, MediaImageType.poster);
        expect(image.instancePath, isNull);
        expect(
          image.remoteUrl,
          Uri.parse('https://artworks.example/posters/79257-6.jpg'),
        );
      });
    }

    test('with nothing but the proxy is left out', () async {
      expect(
        await _imagesOf({
          'coverType': 'poster',
          'url': '/MediaCoverProxy/$_hash/79257-6.jpg',
        }),
        isEmpty,
      );
    });

    test('of a series held is read through the API', () async {
      final series = (await _search(Harness()))[_held]!;

      final poster = series.images.singleWhere(
        (image) => image.type == MediaImageType.poster,
      );
      expect(
        poster.instancePath,
        'api/v3/mediacover/1/poster.jpg?lastWrite=639312965968790041',
      );
      final uri = Uri.parse(poster.instancePath!);
      expect(
        allowList.permits(
          ServiceRequest(
            HttpMethod.get,
            uri.path,
            query: uri.queryParametersAll,
          ),
        ),
        isTrue,
      );
    });
  });

  group('lookup failures', () {
    test('of the client are passed on', () async {
      final harness = Harness();
      harness.server.goOffline();

      expect(await failureOf(harness.lookup.lookup(_term)), isA<Unreachable>());
    });

    for (final (status, failure) in [
      (401, isA<AuthFailed>()),
      (500, isA<ServerError>()),
      (503, isA<ServerError>()),
    ]) {
      test('a $status is passed on and not asked again here', () async {
        final harness = Harness();
        harness.server.always = FakeSonarr.body('{}', status: status);

        expect(await failureOf(harness.lookup.lookup(_term)), failure);
        expect(harness.server.requests, hasLength(1));
      });
    }

    for (final (name, body) in [
      ('not JSON', '{"title":'),
      ('not a list', '{}'),
      ('a list of something else', '[1]'),
      ('a result without a title', '[{"tvdbId": 1}]'),
    ]) {
      test('$name is malformed', () async {
        final harness = Harness();
        harness.server.overrides['series/lookup'] = FakeSonarr.body(body);

        expect(
          await failureOf(harness.lookup.lookup(_term)),
          isA<MalformedResponse>(),
        );
      });
    }
  });
}
