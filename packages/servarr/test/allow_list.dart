/// The requests the shared client may make for what is tested here.
///
/// `servarr` may not import a module, so this repeats, no wider, the entries of
/// the Radarr and Sonarr allow-lists (`packages/modules/*/test/allow_list.dart`)
/// that the client's requests use. The modules' lists stay the authority.
library;

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';

const _any = ParamRule.any();
const _nonEmpty = ParamRule.nonEmpty();
const _flag = ParamRule.only({'true', 'false'}, required: false);
const _statedFlag = ParamRule.only({'true', 'false'});

const _queueRemoval = {
  'removeFromClient': _statedFlag,
  'blocklist': _statedFlag,
  'skipRedownload': _flag,
};

const _ids = BodyRule.jsonObject({'ids': _nonEmpty});

/// What activity and manual import add (T069).
final _activity = [
  for (final path in ['language', 'qualitydefinition'])
    AllowedRequest.read('api/v3/$path'),
  AllowedRequest.read('api/v3/history/since', query: {'date': _nonEmpty}),
  AllowedRequest.read(
    'api/v3/blocklist',
    query: {
      'page': _any,
      'pageSize': _any,
      'sortKey': _any,
      'sortDirection': _any,
    },
  ),
  // Narrower than the modules: without a download the server lists a folder.
  AllowedRequest.read(
    'api/v3/manualimport',
    query: {'downloadId': _nonEmpty, 'filterExistingFiles': _flag},
  ),
  AllowedRequest.write(
    HttpMethod.delete,
    'api/v3/queue/{id}',
    query: _queueRemoval,
  ),
  AllowedRequest.write(
    HttpMethod.delete,
    'api/v3/queue/bulk',
    query: _queueRemoval,
    body: _ids,
  ),
  AllowedRequest.write(HttpMethod.post, 'api/v3/queue/grab/{id}'),
  AllowedRequest.write(HttpMethod.post, 'api/v3/history/failed/{id}'),
  AllowedRequest.write(HttpMethod.delete, 'api/v3/blocklist/{id}'),
  AllowedRequest.write(HttpMethod.delete, 'api/v3/blocklist/bulk', body: _ids),
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/command',
    body: const BodyRule.jsonObject({
      'name': ParamRule.only({'ManualImport'}),
      'files': _nonEmpty,
    }),
  ),
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/manualimport',
    body: const BodyRule.json(),
  ),
];

/// `POST command` with one command name and its targets.
AllowedRequest _command(String name, List<String> targets) =>
    AllowedRequest.write(
      HttpMethod.post,
      'api/v3/command',
      body: BodyRule.jsonObject({
        'name': ParamRule.only({name}),
        for (final target in targets) target: _nonEmpty,
      }),
    );

/// What releases, commands and edits add (T085).
final _manage = [
  AllowedRequest.read('api/v3/release', query: {'movieId': _nonEmpty}),
  AllowedRequest.read('api/v3/release', query: {'episodeId': _nonEmpty}),
  AllowedRequest.read(
    'api/v3/release',
    query: {'seriesId': _nonEmpty, 'seasonNumber': _nonEmpty},
  ),
  // A grab names the release; for one the server could not match, also what
  // was searched for. Any further field could make it download as something
  // else.
  for (final target in const <List<String>>[
    [],
    ['movieId'],
    ['episodeId'],
    ['seriesId', 'seasonNumber'],
  ])
    AllowedRequest.write(
      HttpMethod.post,
      'api/v3/release',
      body: BodyRule.jsonObject({
        'guid': _nonEmpty,
        'indexerId': _nonEmpty,
        for (final field in target) field: _nonEmpty,
      }, closed: true),
    ),
  _command('MoviesSearch', ['movieIds']),
  _command('RefreshMovie', ['movieIds']),
  _command('RescanMovie', ['movieId']),
  _command('EpisodeSearch', ['episodeIds']),
  _command('SeasonSearch', ['seriesId', 'seasonNumber']),
  _command('SeriesSearch', ['seriesId']),
  _command('RefreshSeries', ['seriesIds']),
  _command('RescanSeries', ['seriesId']),
  for (final kind in ['movie', 'series']) ...[
    AllowedRequest.read('api/v3/$kind/{id}'),
    AllowedRequest.write(
      HttpMethod.put,
      'api/v3/$kind/{id}',
      body: const BodyRule.jsonObject({}),
    ),
  ],
  AllowedRequest.write(
    HttpMethod.put,
    'api/v3/movie/editor',
    body: const BodyRule.jsonObject({'movieIds': _nonEmpty}),
  ),
  AllowedRequest.write(
    HttpMethod.put,
    'api/v3/series/editor',
    body: const BodyRule.jsonObject({'seriesIds': _nonEmpty}),
  ),
];

/// The list for a service whose include-unknown flag is [includeUnknown].
AllowList allowList(String includeUnknown) => AllowList([
  for (final path in [
    'system/status',
    'health',
    'qualityprofile',
    'rootfolder',
    'tag',
  ])
    AllowedRequest.read('api/v3/$path'),
  ..._activity,
  ..._manage,
  AllowedRequest.read(
    'api/v3/queue',
    query: {
      'page': _any,
      'pageSize': _any,
      'sortKey': _any,
      'sortDirection': _any,
      includeUnknown: const ParamRule.only({'true'}),
    },
  ),
  AllowedRequest.read(
    'api/v3/history',
    query: {
      'page': _any,
      'pageSize': _any,
      'sortKey': _any,
      'sortDirection': _any,
      'episodeId': _any,
    },
  ),
  AllowedRequest.read(
    'api/v3/history/movie',
    query: {'movieId': const ParamRule.nonEmpty()},
  ),
  AllowedRequest.read(
    'api/v3/history/series',
    query: {'seriesId': const ParamRule.nonEmpty()},
  ),
  AllowedRequest.read('api/v3/command/{id}'),
]);
