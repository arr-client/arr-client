import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../gen_large_library.dart';

// Property names of the upstream schemas, from `openapi.json` of Radarr
// (src/Radarr.Api.V3) and Sonarr (src/Sonarr.Api.V3). Only those the generator
// may use are listed.
const _movieFields = {
  'id', 'title', 'originalTitle', 'originalLanguage', 'alternateTitles', //
  'secondaryYearSourceId', 'sortTitle', 'sizeOnDisk', 'status', 'overview',
  'inCinemas', 'physicalRelease', 'digitalRelease', 'releaseDate', 'images',
  'year', 'youTubeTrailerId', 'studio', 'path', 'qualityProfileId', 'hasFile',
  'movieFileId', 'monitored', 'minimumAvailability', 'isAvailable',
  'folderName', 'runtime', 'cleanTitle', 'imdbId', 'tmdbId', 'titleSlug',
  'rootFolderPath', 'certification', 'genres', 'keywords', 'tags', 'added',
  'ratings', 'popularity', 'movieFile', 'statistics',
};
const _seriesFields = {
  'id', 'title', 'alternateTitles', 'sortTitle', 'status', 'ended', //
  'overview', 'nextAiring', 'previousAiring', 'network', 'airTime', 'images',
  'originalLanguage', 'seasons', 'year', 'path', 'qualityProfileId',
  'seasonFolder', 'monitored', 'monitorNewItems', 'useSceneNumbering',
  'runtime', 'tvdbId', 'tvRageId', 'tvMazeId', 'tmdbId', 'firstAired',
  'lastAired', 'seriesType', 'cleanTitle', 'imdbId', 'titleSlug',
  'rootFolderPath', 'certification', 'genres', 'tags', 'added', 'ratings',
  'statistics',
};
const _episodeFields = {
  'id', 'seriesId', 'tvdbId', 'episodeFileId', 'seasonNumber', //
  'episodeNumber', 'absoluteEpisodeNumber', 'title', 'airDate', 'airDateUtc',
  'runtime', 'overview', 'hasFile', 'monitored', 'unverifiedSceneNumbering',
};

void main() {
  late final List<Map<String, Object>> movies;
  late final List<Map<String, Object>> series;
  late final List<Map<String, Object>> episodes;

  setUpAll(() {
    movies = generateMovies();
    series = generateSeries();
    episodes = [for (final s in series) ...generateEpisodes(s['id']! as int)];
  });

  Set<Object?> values(List<Map<String, Object>> records, String field) => {
    for (final record in records) record[field],
  };

  test('has the sizes of SC-004 and 100,000 episodes', () {
    expect(movies, hasLength(10000));
    expect(series, hasLength(1000));
    expect(episodes, hasLength(100000));
    expect(values(movies, 'id'), hasLength(10000));
    expect(values(movies, 'tmdbId'), hasLength(10000));
    expect(values(movies, 'title'), hasLength(10000));
    expect(values(series, 'tvdbId'), hasLength(1000));
    expect(values(episodes, 'id'), hasLength(100000));
  });

  test('uses only upstream field names', () {
    Set<String> keys(List<Map<String, Object>> records) => {
      for (final record in records) ...record.keys,
    };
    expect(keys(movies), _movieFields);
    expect(keys(series), _seriesFields);
    expect(keys(episodes), _episodeFields);
  });

  test('covers the states a library screen has to show', () {
    expect(values(movies, 'status'), {
      'tba',
      'announced',
      'inCinemas',
      'released',
    });
    expect(values(movies, 'hasFile'), {true, false});
    expect(values(movies, 'monitored'), {true, false});
    expect(values(series, 'status'), {'upcoming', 'continuing', 'ended'});
    expect(values(series, 'seriesType'), {'standard', 'daily', 'anime'});
    expect(values(series, 'monitored'), {true, false});
    expect(values(episodes, 'hasFile'), {true, false});
  });

  test('keeps files, sizes and dates consistent', () {
    for (final movie in movies) {
      final hasFile = movie['hasFile']! as bool;
      expect(movie.containsKey('movieFile'), hasFile);
      expect(movie['sizeOnDisk'], hasFile ? greaterThan(0) : 0);
    }
    for (final episode in episodes) {
      if (episode['hasFile']! as bool) {
        expect(
          (episode['airDateUtc']! as String).compareTo('2027'),
          isNegative,
        );
      }
    }
  });

  test('gives series statistics that match their episodes', () {
    for (final s in series) {
      final own = generateEpisodes(s['id']! as int);
      final statistics = s['statistics']! as Map<String, Object>;
      final seasons = s['seasons']! as List<Map<String, Object>>;
      final files = own.where((e) => e['hasFile'] == true).length;

      expect(statistics['totalEpisodeCount'], own.length);
      expect(statistics['episodeFileCount'], files);
      expect(statistics['seasonCount'], seasons.length);
      expect(
        seasons.fold<int>(0, (sum, season) {
          final counts = season['statistics']! as Map<String, Object>;
          return sum + (counts['totalEpisodeCount']! as int);
        }),
        own.length,
      );
    }
  });

  test('is obviously fake and names no real host', () {
    for (final record in [...movies, ...series, ...episodes]) {
      expect(record['title'], contains('(Fake '));
    }
    final text = jsonEncode([movies.take(100).toList(), series.first]);
    for (final url in RegExp(r'https?://[^/"]+').allMatches(text)) {
      expect(url[0], endsWith('.invalid'));
    }
  });

  test('writes the same files on every run', () async {
    final temp = await Directory.systemTemp.createTemp('large_library');
    addTearDown(() => temp.delete(recursive: true));
    Future<Map<String, String>> run(String name) async {
      final output = Directory('${temp.path}/$name');
      await writeLibrary(output, movies: 30, series: 10);
      return {
        for (final file in output.listSync(recursive: true).whereType<File>())
          file.path.substring(output.path.length + 1): file.readAsStringSync(),
      };
    }

    final first = await run('first');
    expect(await run('second'), first);
    expect(first.keys.toSet(), {
      'movie.json',
      'series.json',
      for (var id = 1; id <= 10; id++) 'episode/$id.json',
    });
    expect(jsonDecode(first['movie.json']!), movies.take(30).toList());
    expect(jsonDecode(first['series.json']!), series.take(10).toList());
    expect(jsonDecode(first['episode/10.json']!), generateEpisodes(10));
  });

  test('gives pinned values, so a change of data is noticed', () {
    // Same numbers on any machine and SDK; update them only on purpose.
    expect(
      [movies.first['title'], movies.first['added']],
      ['Jagged Anchor (Fake 00001)', '2025-07-16T17:40:00Z'],
    );
    expect(series.first['title'], 'Yellow Island (Fake 00001)');
    expect(episodes.first['airDateUtc'], '1998-01-01T20:00:00Z');
  });
}
