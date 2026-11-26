// Automatic and manual search (FR-050, spec story 10 scenario 2), against
// recorded answers.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _movie = SubtitleMedia.movie(2);
const _episode = SubtitleMedia.episode(seriesId: 1, episodeId: 3);
const _series = SubtitleMedia.series(1);

void main() {
  group('automatic search', () {
    for (final (name, language, forced, hi) in const [
      ('a language', SubtitleLanguage(code: 'fr'), 'false', 'false'),
      ('forced', SubtitleLanguage(code: 'it', forced: true), 'true', 'false'),
      (
        'hearing impaired',
        SubtitleLanguage(code: 'de', hi: true),
        'false',
        'true',
      ),
    ]) {
      test('asks for $name of a movie', () async {
        final harness = Harness();

        await accepted(harness.subtitles.autoSearch(_movie, language));

        final request = harness.server.requests.single;
        expect(asked(request), 'PATCH movies/subtitles');
        expect(queryOf(request), {'radarrid': '2'});
        final form = formOf(request);
        expect(form.keys, unorderedEquals(['language', 'forced', 'hi']));
        expect(form['language'], language.code);
        expect(form['forced']!.toLowerCase(), forced);
        expect(form['hi']!.toLowerCase(), hi);
      });
    }

    test('asks for a language of an episode', () async {
      final harness = Harness();

      await accepted(
        harness.subtitles.autoSearch(
          _episode,
          const SubtitleLanguage(code: 'es'),
        ),
      );

      final request = harness.server.requests.single;
      expect(asked(request), 'PATCH episodes/subtitles');
      expect(queryOf(request), {'seriesid': '1', 'episodeid': '3'});
      expect(formOf(request)['language'], 'es');
    });

    test('is not offered for a whole series', () async {
      final harness = Harness();

      await failureOf(
        harness.subtitles.autoSearch(
          _series,
          const SubtitleLanguage(code: 'es'),
        ),
      );

      expect(harness.server.requests, isEmpty);
    });

    for (final failure in <ServiceFailure>[
      const NotFound(),
      const Conflict(),
      const OutcomeUnknown(),
      const Unreachable(),
    ]) {
      test('passes on ${failure.runtimeType}, once', () async {
        final harness = Harness()..server.down = failedAnswer(failure);

        expect(
          await failureOf(
            harness.subtitles.autoSearch(
              _movie,
              const SubtitleLanguage(code: 'es'),
            ),
          ),
          same(failure),
        );
        expect(harness.server.requests, hasLength(1));
      });
    }
  });

  group('manual search', () {
    for (final version in versions) {
      for (final (media, route, name, query)
          in const <(SubtitleMedia, String, String, Map<String, String>)>[
            (_movie, 'movies', 'providers_movies', {'radarrid': '2'}),
            (_episode, 'episodes', 'providers_episodes', {'episodeid': '3'}),
          ]) {
        test('lists what $version finds for $route', () async {
          final harness = Harness(version);

          final found = await succeed(harness.subtitles.manualSearch(media));

          final wire = records(name, version);
          expect(found, hasLength(wire.length));
          for (final (index, candidate) in found.indexed) {
            final record = wire[index];
            expect(candidate.provider, record['provider']);
            expect(candidate.language.code, record['language']);
            expect(candidate.language.forced, record['forced'] == 'True');
            expect(candidate.language.hi, record['hearing_impaired'] == 'True');
            expect(candidate.score, record['score']);
            expect(candidate.matches, record['matches']);
            expect(candidate.dontMatches, record['dont_matches']);
            expect(candidate.originalFormat, record['original_format']);
            expect(candidate.token, record['subtitle']);
          }
          final request = harness.server.requests.single;
          expect(asked(request), 'GET providers/$route');
          expect(queryOf(request), query);
          // The server asks every provider before it answers.
          expect(request.timeout, greaterThan(const Duration(seconds: 30)));
        });
      }
    }

    test('reads flags, regions and what does not match', () async {
      final record = records('providers_movies').first;
      final harness = Harness();
      harness.server.routes['GET providers/movies'] = jsonAnswer({
        'data': [
          {
            ...record,
            'language': 'pt-BR:hi',
            'hearing_impaired': 'True',
            'forced': 'False',
            'dont_matches': ['release_group', 'source'],
            'score': 87,
          },
          {...record, 'language': 'en:forced', 'forced': 'True'},
        ],
      });

      final found = await succeed(harness.subtitles.manualSearch(_movie));

      expect(found.map((candidate) => tag(candidate.language)), [
        'pt-BR:hi',
        'en:forced',
      ]);
      expect(found.first.dontMatches, ['release_group', 'source']);
      expect(found.first.score, 87);
    });

    // Bazarr 1.5 has none for a languages profile that never set it.
    for (final (name, change)
        in <(String, void Function(Map<String, Object?>))>[
          ('null', (record) => record['original_format'] = null),
          ('missing', (record) => record.remove('original_format')),
        ]) {
      test('reads a $name original format as False', () async {
        final record = records('providers_movies', '1.5.0').first;
        change(record);
        final harness = Harness('1.5.0');
        harness.server.routes['GET providers/movies'] = jsonAnswer({
          'data': [record],
        });

        final found = await succeed(harness.subtitles.manualSearch(_movie));

        expect(found.single.originalFormat, 'False');
      });
    }

    test('shows that nothing was found', () async {
      final harness = Harness();
      harness.server.routes['GET providers/movies'] = jsonAnswer({
        'data': <Object?>[],
      });

      expect(await succeed(harness.subtitles.manualSearch(_movie)), isEmpty);
    });

    test('is not offered for a whole series', () async {
      final harness = Harness();

      await failureOf(harness.subtitles.manualSearch(_series));

      expect(harness.server.requests, isEmpty);
    });

    test('says a movie the server does not know is not found', () async {
      final harness = Harness();
      harness.server.routes['GET providers/movies'] = failedAnswer(
        const NotFound(),
        status: 404,
        body: recorded('not_found'),
      );

      expect(
        await failureOf(harness.subtitles.manualSearch(_movie)),
        isA<NotFound>(),
      );
    });

    // Also what throttled providers get.
    test('passes on a server failure', () async {
      const failure = ServerError(statusCode: 500);
      final harness = Harness()
        ..server.down = failedAnswer(
          failure,
          status: 500,
          body: '"All providers are throttled"',
        );

      expect(
        await failureOf(harness.subtitles.manualSearch(_movie)),
        same(failure),
      );
    });

    for (final body in ['{"data":[', '[]', '{"data":[{"language":"en"}]}']) {
      test('cannot understand $body', () async {
        final harness = Harness()..server.down = textAnswer(body);

        expect(
          await failureOf(harness.subtitles.manualSearch(_movie)),
          isA<MalformedResponse>(),
        );
      });
    }
  });
}
