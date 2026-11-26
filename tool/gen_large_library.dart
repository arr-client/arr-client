/// Generates a large, obviously fake library for the performance checks of
/// SC-003 and SC-004:
///
///     dart run tool/gen_large_library.dart [output directory]
///
/// The default output directory is `build/large_library`, which git ignores:
///
///     movie.json         Radarr `GET /api/v3/movie`: 10,000 movies
///     series.json        Sonarr `GET /api/v3/series`: 1,000 series
///     episode/<id>.json  Sonarr `GET /api/v3/episode?seriesId=<id>`:
///                        100,000 episodes in all
///
/// Field names follow `MovieResource`, `SeriesResource` and `EpisodeResource`
/// in the services' `openapi.json`. Like the services, it leaves out fields that
/// have no value.
///
/// Every value is computed from the record's id, with no clock and no
/// `Random`, so each run gives the same bytes. Dates before 2027 count as past
/// and dates from 2090 as future.
///
/// This file imports only the SDK, so a test can also import it and build the
/// records in memory.
library;

import 'dart:convert';
import 'dart:io';

const movieCount = 10000;
const seriesCount = 1000;

/// Episodes of ten consecutive series; they average 100.
const _episodeCounts = [8, 10, 12, 24, 36, 50, 80, 130, 250, 400];
const _episodesPerSeason = 20;

Future<void> main(List<String> args) async {
  if (args.length > 1 || args.any((arg) => arg.startsWith('-'))) {
    stderr.writeln('Usage: dart run tool/gen_large_library.dart [directory]');
    exitCode = 64;
    return;
  }
  final output = Directory(args.firstOrNull ?? 'build/large_library');
  await writeLibrary(output);
  stdout.writeln('Wrote the fake library to ${output.path}');
}

/// Writes the files listed at the top of this file into [output].
Future<void> writeLibrary(
  Directory output, {
  int movies = movieCount,
  int series = seriesCount,
}) async {
  final episodes = Directory('${output.path}/episode');
  await episodes.create(recursive: true);
  Future<void> write(String path, List<Map<String, Object>> records) =>
      File(path).writeAsString(jsonEncode(records));

  await write('${output.path}/movie.json', generateMovies(count: movies));
  await write('${output.path}/series.json', generateSeries(count: series));
  for (var id = 1; id <= series; id++) {
    await write('${episodes.path}/$id.json', generateEpisodes(id));
  }
}

/// Movies with ids 1 to [count].
List<Map<String, Object>> generateMovies({int count = movieCount}) => [
  for (var id = 1; id <= count; id++) _movie(id),
];

/// Series with ids 1 to [count], with statistics that match their episodes.
List<Map<String, Object>> generateSeries({int count = seriesCount}) => [
  for (var id = 1; id <= count; id++) _series(id),
];

/// The episodes of one series, in season and episode order.
List<Map<String, Object>> generateEpisodes(int seriesId) {
  final count = _episodeCounts[(seriesId - 1) % _episodeCounts.length];
  final status = _seriesStatus(seriesId);
  final type = _seriesType(seriesId);
  final monitored = _seriesMonitored(seriesId);
  // The latest possible start still ends a 20 season series before 2027.
  final start = status == 'upcoming'
      ? DateTime.utc(2090, 1, 1, 20)
      : DateTime.utc(1970 + _pick(seriesId, 20, 30), 1, 1, 20);
  // A continuing series has its last three episodes still to come.
  final aired = switch (status) {
    'upcoming' => 0,
    'continuing' => count - 3,
    _ => count,
  };

  return [
    for (var index = 0; index < count; index++)
      () {
        final id = seriesId * 1000 + index + 1;
        final season = index ~/ _episodesPerSeason + 1;
        final number = index % _episodesPerSeason + 1;
        final isAired = index < aired;
        final airDate = status == 'continuing' && !isAired
            ? DateTime.utc(2090, 1, 1 + 7 * (index - aired), 20)
            : start.add(Duration(days: 365 * (season - 1) + 7 * (number - 1)));
        final hasFile = isAired && _pick(id, 21, 10) < 8;
        return <String, Object>{
          'id': id,
          'seriesId': seriesId,
          'tvdbId': 900000000 + id,
          'episodeFileId': hasFile ? id : 0,
          'seasonNumber': season,
          'episodeNumber': number,
          if (type == 'anime') 'absoluteEpisodeNumber': index + 1,
          'title': '${_name(id, 22)} (Fake episode $number)',
          'airDate': _utc(airDate).substring(0, 10),
          'airDateUtc': _utc(airDate),
          'runtime': _seriesRuntime(seriesId),
          'overview': _overview('episode', id),
          'hasFile': hasFile,
          'monitored': monitored && _pick(id, 23, 10) < 9,
          'unverifiedSceneNumbering': false,
        };
      }(),
  ];
}

Map<String, Object> _movie(int id) {
  final name = _name(id, 1);
  final title = '$name (Fake ${_padded(id)})';
  final status = switch (_pick(id, 2, 20)) {
    0 => 'tba',
    1 => 'announced',
    2 => 'inCinemas',
    _ => 'released',
  };
  final year = switch (status) {
    'tba' => 0,
    'announced' => 2090 + _pick(id, 3, 10),
    'inCinemas' => 2026,
    _ => 1950 + _pick(id, 3, 76),
  };
  final released = DateTime.utc(
    year,
    1 + _pick(id, 4, 11),
    1 + _pick(id, 5, 28),
  );
  final hasFile = status == 'released' && _pick(id, 6, 10) < 7;
  final size = hasFile ? 700000000 + _mix(id, 7) * 4 : 0;
  final runtime = 70 + _pick(id, 8, 110);
  final folder = year == 0 ? title : '$title ($year)';
  final path = '/fake/movies/$folder';
  final added = _added(id);
  const language = {'id': 1, 'name': 'English'};

  return {
    'id': id,
    'title': title,
    'originalTitle': title,
    'originalLanguage': language,
    'alternateTitles': <Object>[],
    'secondaryYearSourceId': 0,
    'sortTitle': title.toLowerCase(),
    'sizeOnDisk': size,
    'status': status,
    'overview': _overview('movie', id),
    if (status != 'tba') 'inCinemas': _utc(released),
    if (status == 'released') ...{
      'digitalRelease': _utc(released.add(const Duration(days: 90))),
      'physicalRelease': _utc(released.add(const Duration(days: 120))),
      'releaseDate': _utc(released.add(const Duration(days: 90))),
    },
    'images': _images(id),
    'year': year,
    'youTubeTrailerId': '',
    'studio': 'Fake Studio ${1 + _pick(id, 9, 40)}',
    'path': path,
    'qualityProfileId': 1 + _pick(id, 10, 4),
    'hasFile': hasFile,
    'movieFileId': hasFile ? id : 0,
    'monitored': _pick(id, 11, 10) < 8,
    'minimumAvailability': 'released',
    'isAvailable': status == 'released',
    'folderName': path,
    'runtime': runtime,
    'cleanTitle': _clean(title),
    'imdbId': 'tt${999000000 + id}',
    'tmdbId': 900000000 + id,
    'titleSlug': '${900000000 + id}',
    'rootFolderPath': '/fake/movies/',
    'certification': const ['G', 'PG', 'PG-13', 'R'][_pick(id, 12, 4)],
    'genres': _genres(id),
    'keywords': <Object>[],
    'tags': _tags(id),
    'added': added,
    'ratings': {
      for (final (salt, source) in const [(13, 'imdb'), (14, 'tmdb')])
        source: {
          'votes': _pick(id, salt, 100000),
          'value': (10 + _pick(id, salt, 90)) / 10,
          'type': 'user',
        },
    },
    'popularity': _pick(id, 15, 10000) / 100,
    if (hasFile)
      'movieFile': {
        'id': id,
        'movieId': id,
        'relativePath': '$folder.mkv',
        'path': '$path/$folder.mkv',
        'size': size,
        'dateAdded': added,
        'sceneName': 'Fake.Release.${_padded(id)}',
        'releaseGroup': 'FAKE',
        'edition': '',
        'languages': [language],
        'quality': {
          'quality': {
            'id': 7,
            'name': 'Bluray-1080p',
            'source': 'bluray',
            'resolution': 1080,
            'modifier': 'none',
          },
          'revision': {'version': 1, 'real': 0, 'isRepack': false},
        },
        'mediaInfo': {
          'audioChannels': 5.1,
          'audioCodec': 'AC3',
          'videoCodec': 'x264',
          'resolution': '1920x1080',
          'runTime': '${runtime ~/ 60}:${_padded(runtime % 60, 2)}:00',
        },
        'qualityCutoffNotMet': false,
      },
    'statistics': {
      'movieFileCount': hasFile ? 1 : 0,
      'sizeOnDisk': size,
      'releaseGroups': [if (hasFile) 'FAKE'],
    },
  };
}

Map<String, Object> _series(int id) {
  final title = '${_name(id, 30)} (Fake ${_padded(id)})';
  final slug = '${_name(id, 30).toLowerCase().replaceAll(' ', '-')}-fake-$id';
  final status = _seriesStatus(id);
  final episodes = generateEpisodes(id);
  final seasonNumbers = {for (final e in episodes) e['seasonNumber']! as int};
  final monitored = _seriesMonitored(id);
  final aired = [
    for (final e in episodes)
      if (_isPast(e)) e['airDateUtc']! as String,
  ];
  final upcoming = [
    for (final e in episodes)
      if (!_isPast(e)) e['airDateUtc']! as String,
  ];
  final firstAired = episodes.first['airDateUtc']! as String;

  return {
    'id': id,
    'title': title,
    'alternateTitles': <Object>[],
    'sortTitle': title.toLowerCase(),
    'status': status,
    'ended': status == 'ended',
    'overview': _overview('series', id),
    if (upcoming.isNotEmpty) 'nextAiring': upcoming.first,
    if (aired.isNotEmpty) 'previousAiring': aired.last,
    'network': 'Fake Network ${1 + _pick(id, 31, 20)}',
    'airTime': '20:00',
    'images': _images(id),
    'originalLanguage': {'id': 1, 'name': 'English'},
    'seasons': [
      for (final season in seasonNumbers)
        {
          'seasonNumber': season,
          'monitored': monitored,
          'statistics': _statistics([
            for (final e in episodes)
              if (e['seasonNumber'] == season) e,
          ]),
        },
    ],
    'year': int.parse(firstAired.substring(0, 4)),
    'path': '/fake/series/$title',
    'qualityProfileId': 1 + _pick(id, 32, 4),
    'seasonFolder': true,
    'monitored': monitored,
    'monitorNewItems': 'all',
    'useSceneNumbering': false,
    'runtime': _seriesRuntime(id),
    'tvdbId': 900000000 + id,
    'tvRageId': 0,
    'tvMazeId': 0,
    'tmdbId': 900000000 + id,
    'firstAired': firstAired,
    if (aired.isNotEmpty) 'lastAired': aired.last,
    'seriesType': _seriesType(id),
    'cleanTitle': _clean(title),
    'imdbId': 'tt${999000000 + id}',
    'titleSlug': slug,
    'rootFolderPath': '/fake/series/',
    'certification': const [
      'TV-G',
      'TV-PG',
      'TV-14',
      'TV-MA',
    ][_pick(id, 33, 4)],
    'genres': _genres(id),
    'tags': _tags(id),
    'added': _added(id),
    'ratings': {
      'votes': _pick(id, 34, 100000),
      'value': (10 + _pick(id, 35, 90)) / 10,
    },
    'statistics': {
      'seasonCount': seasonNumbers.length,
      ..._statistics(episodes),
    },
  };
}

/// The counts Sonarr reports for a season or a series. `episodeCount` holds the
/// episodes that have a file, or are monitored and have aired.
Map<String, Object> _statistics(List<Map<String, Object>> episodes) {
  var files = 0;
  var counted = 0;
  var size = 0;
  for (final e in episodes) {
    final hasFile = e['hasFile']! as bool;
    if (hasFile) {
      files++;
      size += 200000000 + _mix(e['id']! as int, 36) ~/ 4;
    }
    if (hasFile || (e['monitored']! as bool && _isPast(e))) counted++;
  }
  return {
    'episodeFileCount': files,
    'episodeCount': counted,
    'totalEpisodeCount': episodes.length,
    'sizeOnDisk': size,
    'releaseGroups': [if (files > 0) 'FAKE'],
    'percentOfEpisodes': counted == 0 ? 0.0 : files * 100 / counted,
  };
}

bool _isPast(Map<String, Object> episode) =>
    (episode['airDateUtc']! as String).compareTo('2027') < 0;

String _seriesStatus(int id) => switch (_pick(id, 40, 20)) {
  0 => 'upcoming',
  < 9 => 'continuing',
  _ => 'ended',
};

String _seriesType(int id) => switch (_pick(id, 41, 20)) {
  0 => 'daily',
  1 || 2 => 'anime',
  _ => 'standard',
};

bool _seriesMonitored(int id) => _pick(id, 42, 10) < 8;

int _seriesRuntime(int id) => const [25, 45, 60][_pick(id, 43, 3)];

/// A stable 32 bit hash. `Random` may change between SDK releases.
int _mix(int id, int salt) {
  var x = (id * 0x9E3779B1 + salt * 0x85EBCA6B) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
  return x ^ (x >> 16);
}

int _pick(int id, int salt, int choices) => _mix(id, salt) % choices;

const _adjectives = [
  'Amber', 'Brisk', 'Crimson', 'Distant', 'Electric', 'Frozen', 'Gilded', //
  'Hollow', 'Ivory', 'Jagged', 'Kindred', 'Lunar', 'Mellow', 'Nimble',
  'Obsidian', 'Paper', 'Quiet', 'Rusty', 'Silver', 'Tangled', 'Umber',
  'Velvet', 'Wandering', 'Yellow',
];
const _nouns = [
  'Anchor', 'Badger', 'Compass', 'Dynamo', 'Ember', 'Falcon', 'Garden', //
  'Harbor', 'Island', 'Juniper', 'Kettle', 'Lantern', 'Meadow', 'Nebula',
  'Orchard', 'Pelican', 'Quarry', 'River', 'Signal', 'Teapot', 'Voyage',
  'Walrus', 'Zeppelin',
];

/// Varied first letters, so sorting and searching have something to do.
String _name(int id, int salt) =>
    '${_adjectives[_pick(id, salt, _adjectives.length)]} '
    '${_nouns[_pick(id, salt + 100, _nouns.length)]}';

String _overview(String kind, int id) => [
  'Generated placeholder text for a fake $kind. Nothing here is real.',
  for (var i = _pick(id, 50, 5); i > 0; i--)
    'The ${_name(id, 50 + i).toLowerCase()} exists only to fill this overview.',
].join(' ');

List<Map<String, String>> _images(int id) => [
  for (final type in const ['poster', 'fanart'])
    {
      'coverType': type,
      'url': '/MediaCover/$id/$type.jpg',
      // .invalid never resolves, so a check run makes no outside requests.
      'remoteUrl': 'https://images.example.invalid/$id/$type.jpg',
    },
];

List<String> _genres(int id) {
  const genres = [
    'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary', //
    'Drama', 'Fantasy', 'Horror', 'Mystery', 'Romance', 'Thriller',
  ];
  final first = _pick(id, 60, genres.length);
  return [genres[first], if (id.isEven) genres[(first + 5) % genres.length]];
}

List<int> _tags(int id) => [if (_pick(id, 61, 4) == 0) 1 + _pick(id, 62, 5)];

String _added(int id) => _utc(
  DateTime.utc(2018).add(Duration(minutes: _pick(id, 63, 8 * 365 * 24 * 60))),
);

String _clean(String title) =>
    title.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

String _padded(int value, [int width = 5]) =>
    value.toString().padLeft(width, '0');

/// The services write times without fractions of a second.
String _utc(DateTime time) => time.toIso8601String().replaceFirst('.000', '');
