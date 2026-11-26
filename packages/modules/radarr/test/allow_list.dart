/// Every request the Radarr module may make (FR-019), from
/// specs/001-arr-companion-app/contracts/upstream-apis.md, with paths and
/// parameter names as in Radarr's v3 API. Adapter tests run through it.
///
/// Anything not here is refused, every configuration write included.
library;

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';

const _any = ParamRule.any();
const _nonEmpty = ParamRule.nonEmpty();
const _flag = ParamRule.only({'true', 'false'}, required: false);
// For a flag whose server default is not what leaving it out should mean.
const _statedFlag = ParamRule.only({'true', 'false'});

const _paging = {
  'page': _any,
  'pageSize': _any,
  'sortKey': _any,
  'sortDirection': _any,
};

const _queueRemoval = {
  // The server removes from the download client unless told not to.
  'removeFromClient': _statedFlag,
  'blocklist': _statedFlag,
  'skipRedownload': _flag,
};

const _ids = BodyRule.jsonObject({'ids': _nonEmpty});

/// `POST command` with one command name. The server runs any command it knows,
/// and some act on the whole library when [target] is left out.
AllowedRequest _command(String name, String target) => AllowedRequest.write(
  HttpMethod.post,
  'api/v3/command',
  body: BodyRule.jsonObject({
    'name': ParamRule.only({name}),
    target: _nonEmpty,
  }),
);

/// The Radarr allow-list.
final allowList = AllowList([
  // Common to the Servarr family.
  for (final path in [
    'system/status',
    'health',
    'diskspace',
    'qualityprofile',
    'rootfolder',
    'tag',
    'language',
    'qualitydefinition',
  ])
    AllowedRequest.read('api/v3/$path'),
  AllowedRequest.read(
    'api/v3/calendar',
    query: {'start': _any, 'end': _any, 'unmonitored': _flag, 'tags': _any},
  ),
  AllowedRequest.read(
    'api/v3/history',
    query: {
      ..._paging,
      'includeMovie': _flag,
      'eventType': _any,
      'downloadId': _any,
      'movieIds': _any,
      'languages': _any,
      'quality': _any,
    },
  ),
  AllowedRequest.read(
    'api/v3/history/since',
    query: {'date': _nonEmpty, 'eventType': _any, 'includeMovie': _flag},
  ),
  for (final path in ['wanted/missing', 'wanted/cutoff'])
    AllowedRequest.read(
      'api/v3/$path',
      query: {..._paging, 'monitored': _flag},
    ),
  AllowedRequest.read(
    'api/v3/queue',
    query: {
      ..._paging,
      // The default hides downloads the server cannot match.
      'includeUnknownMovieItems': const ParamRule.only({'true'}),
      'includeMovie': _flag,
      'movieIds': _any,
      'protocol': _any,
      'languages': _any,
      'quality': _any,
      'status': _any,
    },
  ),
  // Has no include-unknown flag: it returns unmatched downloads too.
  AllowedRequest.read(
    'api/v3/queue/details',
    query: {'movieId': _any, 'includeMovie': _flag},
  ),
  AllowedRequest.read(
    'api/v3/blocklist',
    query: {..._paging, 'movieIds': _any, 'protocols': _any},
  ),
  // Without a movie the server answers with its RSS feeds instead.
  AllowedRequest.read('api/v3/release', query: {'movieId': _nonEmpty}),
  AllowedRequest.read('api/v3/command/{id}'),
  AllowedRequest.read(
    'api/v3/manualimport',
    query: {
      'folder': _any,
      'downloadId': _any,
      'movieId': _any,
      'filterExistingFiles': _flag,
    },
  ),
  // The cache buster of the image addresses the server returns: `lastWrite` up
  // to Radarr 6.0, `h` in later releases.
  AllowedRequest.read(
    'api/v3/mediacover/{movieId}/**',
    query: {'h': _any, 'lastWrite': _any},
  ),

  // Library, lookup and item history.
  AllowedRequest.read('api/v3/movie', query: {'tmdbId': _any}),
  AllowedRequest.read('api/v3/movie/{id}'),
  AllowedRequest.read(
    'api/v3/moviefile',
    query: {'movieId': _any, 'movieFileIds': _any},
  ),
  AllowedRequest.read('api/v3/credit', query: {'movieId': _nonEmpty}),
  AllowedRequest.read('api/v3/movie/lookup', query: {'term': _nonEmpty}),
  AllowedRequest.read(
    'api/v3/history/movie',
    query: {'movieId': _nonEmpty, 'eventType': _any, 'includeMovie': _flag},
  ),

  // Queue, history, releases and blocklist.
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
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/release',
    body: const BodyRule.jsonObject({
      'guid': _nonEmpty,
      'indexerId': _nonEmpty,
    }),
  ),
  AllowedRequest.write(HttpMethod.delete, 'api/v3/blocklist/{id}'),
  AllowedRequest.write(HttpMethod.delete, 'api/v3/blocklist/bulk', body: _ids),

  // Commands and manual import.
  _command('MoviesSearch', 'movieIds'),
  _command('RefreshMovie', 'movieIds'),
  _command('RescanMovie', 'movieId'),
  _command('ManualImport', 'files'),
  // Takes a list of candidates.
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/manualimport',
    body: const BodyRule.json(),
  ),

  // Add, edit, delete and file delete. Monitoring is an edit of the movie.
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/movie',
    body: const BodyRule.jsonObject({}),
  ),
  AllowedRequest.write(
    HttpMethod.put,
    'api/v3/movie/{id}',
    body: const BodyRule.jsonObject({}),
  ),
  AllowedRequest.write(
    HttpMethod.delete,
    'api/v3/movie/{id}',
    query: {'deleteFiles': _flag, 'addImportExclusion': _flag},
  ),
  AllowedRequest.write(
    HttpMethod.put,
    'api/v3/movie/editor',
    body: const BodyRule.jsonObject({'movieIds': _nonEmpty}),
  ),
  AllowedRequest.write(HttpMethod.delete, 'api/v3/moviefile/{id}'),
]);
