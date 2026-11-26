// Deleting and synchronizing a subtitle file (FR-050, spec story 10
// scenario 4), against recorded answers.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _movieFile = SubtitleFile(
  mediaType: SubtitleMediaType.movie,
  mediaId: 2,
  path: '/media/A Film (2000)/A Film & more? #1.en.srt',
  language: SubtitleLanguage(code: 'en'),
);

const _episodeFile = SubtitleFile(
  mediaType: SubtitleMediaType.episode,
  mediaId: 3,
  seriesId: 1,
  path: '/media/A Show/S01E03.de.hi.srt',
  language: SubtitleLanguage(code: 'de', hi: true),
);

const _forcedFile = SubtitleFile(
  mediaType: SubtitleMediaType.movie,
  mediaId: 2,
  path: '/media/film.it.forced.srt',
  language: SubtitleLanguage(code: 'it', forced: true),
);

/// An episode file without the series the server needs for a delete.
const _orphan = SubtitleFile(
  mediaType: SubtitleMediaType.episode,
  mediaId: 3,
  path: '/media/A Show/S01E03.en.srt',
  language: SubtitleLanguage(code: 'en'),
);

String _flag(bool value) => value ? 'True' : 'False';

void main() {
  group('delete', () {
    for (final (file, route, query) in const [
      (_movieFile, 'movies', {'radarrid': '2'}),
      (_forcedFile, 'movies', {'radarrid': '2'}),
      (_episodeFile, 'episodes', {'seriesid': '1', 'episodeid': '3'}),
    ]) {
      test('names the file ${file.path}', () async {
        final harness = Harness();

        await accepted(harness.subtitles.delete(file));

        final request = harness.server.requests.single;
        expect(asked(request), 'DELETE $route/subtitles');
        expect(queryOf(request), query);
        final form = formOf(request);
        expect(
          form.keys,
          unorderedEquals(['language', 'forced', 'hi', 'path']),
        );
        expect(form['language'], file.language.code);
        expect(form['forced']!.toLowerCase(), '${file.language.forced}');
        expect(form['hi']!.toLowerCase(), '${file.language.hi}');
        // As the server gave it: the client encodes it.
        expect(form['path'], file.path);
      });
    }

    test('deletes a file as it was listed', () async {
      final harness = Harness();
      final episodes = await succeed(harness.subtitles.browseEpisodes(1));

      await accepted(harness.subtitles.delete(episodes.first.files.first));

      final wire = records('episodes_series_1').first;
      final listed = (wire['subtitles']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .first;
      final request = harness.server.requests.last;
      expect(queryOf(request), {
        'seriesid': '${wire['sonarrSeriesId']}',
        'episodeid': '${wire['sonarrEpisodeId']}',
      });
      expect(formOf(request)['path'], listed['path']);
    });

    test('sends nothing for an episode without its series', () async {
      final harness = Harness();

      await failureOf(harness.subtitles.delete(_orphan));

      expect(harness.server.requests, isEmpty);
    });
  });

  group('sync', () {
    for (final (file, type) in const [
      (_movieFile, 'movie'),
      (_forcedFile, 'movie'),
      (_episodeFile, 'episode'),
    ]) {
      test('names the file ${file.path}', () async {
        final harness = Harness();

        await accepted(harness.subtitles.sync(file));

        final request = harness.server.requests.single;
        expect(asked(request), 'PATCH subtitles');
        expect(queryOf(request), {'action': 'sync'});
        expect(formOf(request), {
          'type': type,
          'id': '${file.mediaId}',
          'language': file.language.code,
          'path': file.path,
          'forced': _flag(file.language.forced),
          'hi': _flag(file.language.hi),
        });
      });
    }
  });

  final writes =
      <
        String,
        (
          String,
          String,
          ServiceResult<void> Function(SubtitleProvider subtitles),
        )
      >{
        'delete': (
          'DELETE movies/subtitles',
          'delete_failed',
          (subtitles) => subtitles.delete(_movieFile),
        ),
        'sync': (
          'PATCH subtitles',
          'sync_failed',
          (subtitles) => subtitles.sync(_movieFile),
        ),
      };
  for (final MapEntry(key: name, value: (route, recording, write))
      in writes.entries) {
    group('a refused $name', () {
      // Recorded for a file that is not there.
      test('is a server failure', () async {
        const failure = ServerError(statusCode: 500);
        final harness = Harness();
        harness.server.routes[route] = failedAnswer(
          failure,
          status: 500,
          body: recorded(recording),
        );

        expect(await failureOf(write(harness.subtitles)), same(failure));
        expect(harness.server.requests, hasLength(1));
      });

      for (final failure in <ServiceFailure>[
        const NotFound(),
        const Conflict(),
        const OutcomeUnknown(),
        const Unreachable(),
        const Forbidden(),
      ]) {
        test('passes on ${failure.runtimeType}, once', () async {
          final harness = Harness()..server.down = failedAnswer(failure);

          expect(await failureOf(write(harness.subtitles)), same(failure));
          expect(harness.server.requests, hasLength(1));
        });
      }
    });
  }
}
