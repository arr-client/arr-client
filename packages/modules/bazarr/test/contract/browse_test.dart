// Browsing titles and the subtitle state of one (FR-050, spec story 10
// scenarios 3 and 4), against recorded answers.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// What is listed as files of a record: what has a path. Embedded tracks have
/// none, and can be neither deleted nor synchronized.
List<Map<String, Object?>> _external(Map<String, Object?> record) => [
  for (final file
      in (record['subtitles']! as List<Object?>).cast<Map<String, Object?>>())
    if (file['path'] != null) file,
];

void _expectFiles(
  SubtitleTitle title,
  Map<String, Object?> record,
  SubtitleMediaType type,
) {
  expect(
    [for (final file in title.files) '${file.path} ${tag(file.language)}'],
    [for (final file in _external(record)) '${file['path']} ${wireTag(file)}'],
  );
  for (final file in title.files) {
    expect(file.mediaType, type);
    if (type == SubtitleMediaType.movie) {
      expect(file.mediaId, record['radarrId']);
      expect(file.seriesId, isNull);
    } else {
      expect(file.mediaId, record['sonarrEpisodeId']);
      expect(file.seriesId, record['sonarrSeriesId']);
    }
  }
}

void _expectMovie(SubtitleTitle title, Map<String, Object?> record) {
  expect(title.media, SubtitleMedia.movie(record['radarrId']! as int));
  expect(title.title, record['title']);
  expect(title.year, int.parse(record['year']! as String));
  final missing = wireTags(record['missing_subtitles']);
  expect(title.missing.map(tag), missing);
  expect(title.missingCount, missing.length);
  _expectFiles(title, record, SubtitleMediaType.movie);
}

void _expectSeries(SubtitleTitle title, Map<String, Object?> record) {
  expect(title.media, SubtitleMedia.series(record['sonarrSeriesId']! as int));
  expect(title.title, record['title']);
  expect(title.year, int.parse(record['year']! as String));
  expect(title.missingCount, record['episodeMissingCount']);
  expect(title.missing, isEmpty);
  expect(title.files, isEmpty);
}

void _expectEpisode(SubtitleTitle title, Map<String, Object?> record) {
  expect(
    title.media,
    SubtitleMedia.episode(
      seriesId: record['sonarrSeriesId']! as int,
      episodeId: record['sonarrEpisodeId']! as int,
    ),
  );
  // Numbered as the server numbers wanted and history entries.
  expect(title.title, contains('${record['season']}x${record['episode']}'));
  expect(title.title, contains(record['title']! as String));
  final missing = wireTags(record['missing_subtitles']);
  expect(title.missing.map(tag), missing);
  expect(title.missingCount, missing.length);
  _expectFiles(title, record, SubtitleMediaType.episode);
}

void main() {
  for (final version in versions) {
    group('Bazarr $version', () {
      test('lists movies in the server order', () async {
        final harness = Harness(version);

        final page = await succeed(harness.subtitles.browseMovies());

        final wire = records('movies', version);
        expect(page.page, 1);
        expect(page.hasMore, isFalse);
        expect(page.items, hasLength(wire.length));
        for (final (index, title) in page.items.indexed) {
          _expectMovie(title, wire[index]);
        }
        final request = harness.server.requests.single;
        expect(asked(request), 'GET movies');
        expect(queryOf(request).keys, unorderedEquals(['start', 'length']));
      });

      test('lists series with how many episodes lack subtitles', () async {
        final harness = Harness(version);

        final page = await succeed(harness.subtitles.browseSeries());

        final wire = records('series', version);
        expect(page.items, hasLength(wire.length));
        for (final (index, title) in page.items.indexed) {
          _expectSeries(title, wire[index]);
        }
        expect(asked(harness.server.requests.single), 'GET series');
      });

      test('lists the episodes of a series', () async {
        final harness = Harness(version);

        final episodes = await succeed(harness.subtitles.browseEpisodes(1));

        final wire = records('episodes_series_1', version);
        expect(episodes, hasLength(wire.length));
        for (final (index, title) in episodes.indexed) {
          _expectEpisode(title, wire[index]);
        }
        final request = harness.server.requests.single;
        expect(asked(request), 'GET episodes');
        expect(queryOf(request), {'seriesid[]': '1'});
      });

      test('reads one movie', () async {
        final harness = Harness(version);
        harness.server.routes['GET movies'] = jsonAnswer(
          fixture('movie_3', version),
        );

        final title = await succeed(
          harness.subtitles.forMedia(const SubtitleMedia.movie(3)),
        );

        _expectMovie(title, records('movie_3', version).single);
        expect(title.files.single.language.hi, isTrue);
        expect(queryOf(harness.server.requests.single), {'radarrid[]': '3'});
      });

      test('reads one series', () async {
        final harness = Harness(version);
        harness.server.routes['GET series'] = jsonAnswer(
          fixture('series_1', version),
        );

        final title = await succeed(
          harness.subtitles.forMedia(const SubtitleMedia.series(1)),
        );

        _expectSeries(title, records('series_1', version).single);
        expect(queryOf(harness.server.requests.single), {'seriesid[]': '1'});
      });

      test('reads one episode', () async {
        final harness = Harness(version);
        harness.server.routes['GET episodes'] = jsonAnswer(
          fixture('episode_2', version),
        );

        final title = await succeed(
          harness.subtitles.forMedia(
            const SubtitleMedia.episode(seriesId: 1, episodeId: 2),
          ),
        );

        _expectEpisode(title, records('episode_2', version).single);
        expect(queryOf(harness.server.requests.single), {'episodeid[]': '2'});
      });
    });
  }

  test('does not offer embedded tracks as files', () async {
    final harness = Harness();
    harness.server.routes['GET movies'] = jsonAnswer(
      fixture('movies_embedded'),
    );
    final wire = records('movies_embedded').single;
    // One file beside the video, and two tracks inside it.
    expect(wire['subtitles'], hasLength(3));

    final title = await succeed(
      harness.subtitles.forMedia(const SubtitleMedia.movie(2)),
    );

    expect(title.files, hasLength(1));
    _expectMovie(title, wire);
  });

  group('paging', () {
    final lists =
        <
          String,
          ServiceResult<ResultPage<SubtitleTitle>> Function(
            SubtitleProvider subtitles,
            int page,
          )
        >{
          'movies': (subtitles, page) => subtitles.browseMovies(page: page),
          'series': (subtitles, page) => subtitles.browseSeries(page: page),
        };
    for (final MapEntry(key: name, value: browse) in lists.entries) {
      test('asks for the pages of $name in turn', () async {
        final harness = Harness();
        harness.server.routes['GET $name'] = jsonAnswer({
          ...fixture(name),
          'total': 10000,
        });

        final first = await succeed(browse(harness.subtitles, 1));
        final third = await succeed(browse(harness.subtitles, 3));

        final [one, three] = harness.server.requests.map(queryOf).toList();
        final length = int.parse(one['length']!);
        // Without a length the server sends the whole library.
        expect(length, greaterThan(0));
        expect(one['start'], '0');
        expect(three['length'], '$length');
        expect(three['start'], '${2 * length}');
        expect(first.hasMore, isTrue);
        expect(third.page, 3);
        expect(third.hasMore, isTrue);
      });
    }

    test('ends after the last entry', () async {
      final harness = Harness();
      await succeed(harness.subtitles.browseMovies());
      final length = int.parse(
        queryOf(harness.server.requests.single)['length']!,
      );
      harness.server.routes['GET movies'] = jsonAnswer({
        ...fixture('movies'),
        'total': length + records('movies').length,
      });

      final second = await succeed(harness.subtitles.browseMovies(page: 2));

      expect(second.hasMore, isFalse);
    });

    test('shows an empty library', () async {
      final harness = Harness();
      harness.server.routes['GET movies'] = jsonAnswer({
        'data': <Object?>[],
        'total': 0,
      });

      final page = await succeed(harness.subtitles.browseMovies());

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('tolerance', () {
    test(
      'ignores fields it does not know, and missing optional ones',
      () async {
        final wire = records('movies').first
          ..['someFutureField'] = {'a': 1}
          ..remove('year')
          ..remove('sceneName');
        final harness = Harness();
        harness.server.routes['GET movies'] = jsonAnswer({
          'data': [wire],
          'total': 1,
        });

        final page = await succeed(harness.subtitles.browseMovies());

        expect(page.items.single.title, wire['title']);
        expect(page.items.single.year, isNull);
      },
    );

    for (final (name, media) in const [
      ('movie', SubtitleMedia.movie(999)),
      ('series', SubtitleMedia.series(999)),
      ('episode', SubtitleMedia.episode(seriesId: 1, episodeId: 999)),
    ]) {
      test('says a $name the server does not know is not found', () async {
        final harness = Harness()
          ..server.down = jsonAnswer({'data': <Object?>[], 'total': 0});

        expect(
          await failureOf(harness.subtitles.forMedia(media)),
          isA<NotFound>(),
        );
      });
    }
  });

  group('failures', () {
    final reads = <String, ServiceResult<Object?> Function(SubtitleProvider)>{
      'movies': (subtitles) => subtitles.browseMovies(),
      'series': (subtitles) => subtitles.browseSeries(),
      'episodes': (subtitles) => subtitles.browseEpisodes(1),
      'one title': (subtitles) =>
          subtitles.forMedia(const SubtitleMedia.movie(1)),
    };
    for (final MapEntry(key: name, value: read) in reads.entries) {
      test('of the client reach the caller for $name', () async {
        const failure = Unreachable();
        final harness = Harness()..server.down = failedAnswer(failure);

        expect(await failureOf(read(harness.subtitles)), same(failure));
      });

      for (final body in [
        '{"data":[',
        '[]',
        '{"data":"none","total":1}',
        '{"data":[{"title":3}],"total":1}',
      ]) {
        test('cannot understand $body for $name', () async {
          final harness = Harness()..server.down = textAnswer(body);

          expect(
            await failureOf(read(harness.subtitles)),
            isA<MalformedResponse>(),
          );
        });
      }
    }
  });
}
