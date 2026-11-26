// Downloading a candidate of a manual search (FR-050, spec story 10
// scenario 2), against recorded answers.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _movie = SubtitleMedia.movie(2);
const _episode = SubtitleMedia.episode(seriesId: 1, episodeId: 3);

SubtitleCandidate _candidate({
  String originalFormat = 'False',
  String token = 'token',
  bool forced = false,
  bool hi = false,
}) => SubtitleCandidate(
  provider: 'someprovider',
  language: SubtitleLanguage(code: 'en', forced: forced, hi: hi),
  score: 90,
  originalFormat: originalFormat,
  token: token,
);

void main() {
  for (final version in versions) {
    for (final (media, route, name, query)
        in const <(SubtitleMedia, String, String, Map<String, String>)>[
          (_movie, 'movies', 'providers_movies', {'radarrid': '2'}),
          (
            _episode,
            'episodes',
            'providers_episodes',
            {'seriesid': '1', 'episodeid': '3'},
          ),
        ]) {
      test('sends back what $version found for $route', () async {
        final harness = Harness(version);
        final found = await succeed(harness.subtitles.manualSearch(media));

        await accepted(harness.subtitles.download(media, found.last));

        final wire = records(name, version).last;
        final request = harness.server.requests.last;
        expect(asked(request), 'POST providers/$route');
        expect(queryOf(request), query);
        final form = formOf(request);
        expect(
          form.keys,
          unorderedEquals([
            'hi',
            'forced',
            'original_format',
            'provider',
            'subtitle',
          ]),
        );
        expect(
          form['hi']!.toLowerCase(),
          (wire['hearing_impaired']! as String).toLowerCase(),
        );
        expect(
          form['forced']!.toLowerCase(),
          (wire['forced']! as String).toLowerCase(),
        );
        expect(form['original_format'], wire['original_format']);
        expect(form['provider'], wire['provider']);
        expect(form['subtitle'], wire['subtitle']);
      });
    }
  }

  test('says forced and hearing impaired', () async {
    final harness = Harness();

    await accepted(
      harness.subtitles.download(_movie, _candidate(forced: true, hi: true)),
    );

    final form = formOf(harness.server.requests.single);
    expect(form['forced']!.toLowerCase(), 'true');
    expect(form['hi']!.toLowerCase(), 'true');
  });

  // 1.5 identifies a candidate by the whole of it.
  test('sends a long token back as it is', () async {
    final token = '${'gASV+/=A' * 10}\n' * 200;
    final harness = Harness('1.5.0');

    await accepted(
      harness.subtitles.download(
        _movie,
        _candidate(token: token, originalFormat: '1'),
      ),
    );

    final request = harness.server.requests.single;
    expect(formOf(request)['subtitle'], token);
    expect(formOf(request)['original_format'], '1');
    expect(request.query.toString(), isNot(contains('gASV')));
  });

  test('takes the answer of 1.5 as accepted', () async {
    final harness = Harness('1.5.0');
    harness.server.routes['POST providers/movies'] = textAnswer('null\n');

    await accepted(harness.subtitles.download(_movie, _candidate()));
  });

  // Bazarr answers a path it does not have with its web interface.
  test('does not take a web page for acceptance', () async {
    final harness = Harness();
    harness.server.routes['POST providers/movies'] = textAnswer(
      '<!doctype html><title>Bazarr</title>',
    );

    expect(
      await failureOf(harness.subtitles.download(_movie, _candidate())),
      isA<ProxyInterception>(),
    );
  });

  test('cannot understand another body', () async {
    final harness = Harness();
    harness.server.routes['POST providers/movies'] = textAnswer('"Busy"');

    expect(
      await failureOf(harness.subtitles.download(_movie, _candidate())),
      isA<MalformedResponse>(),
    );
  });

  test('is not offered for a whole series', () async {
    final harness = Harness();

    await failureOf(
      harness.subtitles.download(const SubtitleMedia.series(1), _candidate()),
    );

    expect(harness.server.requests, isEmpty);
  });

  // A write is sent at most once, whatever happens to it.
  for (final failure in <ServiceFailure>[
    const NotFound(),
    const ServerError(statusCode: 500),
    const Conflict(),
    const OutcomeUnknown(),
    const Unreachable(),
    const AuthFailed(),
  ]) {
    test('passes on ${failure.runtimeType}, and does not try again', () async {
      final harness = Harness()..server.down = failedAnswer(failure);

      expect(
        await failureOf(harness.subtitles.download(_movie, _candidate())),
        same(failure),
      );
      expect(harness.server.requests, hasLength(1));
    });
  }
}
