/// Every request the Sonarr module may make (FR-019), from
/// specs/001-arr-companion-app/contracts/upstream-apis.md, with paths and
/// parameter names as in Sonarr's v3 API. Adapter tests run through it.
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
/// and some act on the whole library when [targets] are left out.
AllowedRequest _command(String name, List<String> targets) =>
    AllowedRequest.write(
      HttpMethod.post,
      'api/v3/command',
      body: BodyRule.jsonObject({
        'name': ParamRule.only({name}),
        for (final target in targets) target: _nonEmpty,
      }),
    );

/// The Sonarr allow-list.
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
    query: {
      'start': _any,
      'end': _any,
      'unmonitored': _flag,
      'includeSeries': _flag,
      'includeEpisodeFile': _flag,
      'includeEpisodeImages': _flag,
      'tags': _any,
    },
  ),
  AllowedRequest.read(
    'api/v3/history',
    query: {
      ..._paging,
      'includeSeries': _flag,
      'includeEpisode': _flag,
      'eventType': _any,
      'episodeId': _any,
      'downloadId': _any,
      'seriesIds': _any,
      'languages': _any,
      'quality': _any,
    },
  ),
  AllowedRequest.read(
    'api/v3/history/since',
    query: {
      'date': _nonEmpty,
      'eventType': _any,
      'includeSeries': _flag,
      'includeEpisode': _flag,
    },
  ),
  AllowedRequest.read(
    'api/v3/wanted/missing',
    query: {
      ..._paging,
      'includeSeries': _flag,
      'includeImages': _flag,
      'monitored': _flag,
    },
  ),
  AllowedRequest.read(
    'api/v3/wanted/cutoff',
    query: {
      ..._paging,
      'includeSeries': _flag,
      'includeEpisodeFile': _flag,
      'includeImages': _flag,
      'monitored': _flag,
    },
  ),
  AllowedRequest.read(
    'api/v3/queue',
    query: {
      ..._paging,
      // The default hides downloads the server cannot match.
      'includeUnknownSeriesItems': const ParamRule.only({'true'}),
      'includeSeries': _flag,
      'includeEpisode': _flag,
      'seriesIds': _any,
      'protocol': _any,
      'languages': _any,
      'quality': _any,
      'status': _any,
    },
  ),
  // Has no include-unknown flag: it returns unmatched downloads too.
  AllowedRequest.read(
    'api/v3/queue/details',
    query: {
      'seriesId': _any,
      'episodeIds': _any,
      'includeSeries': _flag,
      'includeEpisode': _flag,
    },
  ),
  AllowedRequest.read(
    'api/v3/blocklist',
    query: {..._paging, 'seriesIds': _any, 'protocols': _any},
  ),
  // An episode or a season: without either the server answers with its RSS
  // feeds instead.
  AllowedRequest.read('api/v3/release', query: {'episodeId': _nonEmpty}),
  AllowedRequest.read(
    'api/v3/release',
    query: {'seriesId': _nonEmpty, 'seasonNumber': _nonEmpty},
  ),
  AllowedRequest.read('api/v3/command/{id}'),
  AllowedRequest.read(
    'api/v3/manualimport',
    query: {
      'folder': _any,
      'downloadId': _any,
      'seriesId': _any,
      'seasonNumber': _any,
      'filterExistingFiles': _flag,
    },
  ),
  // The cache buster of the image addresses the server returns: `lastWrite` in
  // Sonarr 4, `h` in Sonarr 5.
  AllowedRequest.read(
    'api/v3/mediacover/{seriesId}/**',
    query: {'h': _any, 'lastWrite': _any},
  ),

  // Library, lookup and item history.
  AllowedRequest.read(
    'api/v3/series',
    query: {'tvdbId': _any, 'includeSeasonImages': _flag},
  ),
  AllowedRequest.read(
    'api/v3/series/{id}',
    query: {'includeSeasonImages': _flag},
  ),
  AllowedRequest.read(
    'api/v3/episode',
    query: {
      'seriesId': _any,
      'seasonNumber': _any,
      'episodeIds': _any,
      'episodeFileId': _any,
      'includeSeries': _flag,
      'includeEpisodeFile': _flag,
      'includeImages': _flag,
    },
  ),
  AllowedRequest.read(
    'api/v3/episodefile',
    query: {'seriesId': _any, 'episodeFileIds': _any},
  ),
  AllowedRequest.read('api/v3/series/lookup', query: {'term': _nonEmpty}),
  AllowedRequest.read(
    'api/v3/history/series',
    query: {
      'seriesId': _nonEmpty,
      'seasonNumber': _any,
      'eventType': _any,
      'includeSeries': _flag,
      'includeEpisode': _flag,
    },
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
  // A grab names the release; for one the server could not match, also what
  // was searched for. Any further field could make it download as something
  // else.
  for (final target in const <List<String>>[
    [],
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
  AllowedRequest.write(HttpMethod.delete, 'api/v3/blocklist/{id}'),
  AllowedRequest.write(HttpMethod.delete, 'api/v3/blocklist/bulk', body: _ids),

  // Commands and manual import.
  _command('EpisodeSearch', ['episodeIds']),
  _command('SeasonSearch', ['seriesId', 'seasonNumber']),
  _command('SeriesSearch', ['seriesId']),
  _command('RefreshSeries', ['seriesIds']),
  _command('RescanSeries', ['seriesId']),
  _command('ManualImport', ['files']),
  // Takes a list of candidates.
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/manualimport',
    body: const BodyRule.json(),
  ),

  // Add, edit and delete. Seasons are monitored by an edit of the series.
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/series',
    body: const BodyRule.jsonObject({}),
  ),
  AllowedRequest.write(
    HttpMethod.put,
    'api/v3/series/{id}',
    body: const BodyRule.jsonObject({}),
  ),
  AllowedRequest.write(
    HttpMethod.delete,
    'api/v3/series/{id}',
    // Both stated: what is deleted never rests on a server default.
    query: {'deleteFiles': _statedFlag, 'addImportListExclusion': _statedFlag},
  ),
  AllowedRequest.write(
    HttpMethod.put,
    'api/v3/series/editor',
    body: const BodyRule.jsonObject({'seriesIds': _nonEmpty}),
  ),

  // Monitoring, monitoring option and file delete.
  AllowedRequest.write(
    HttpMethod.put,
    'api/v3/episode/monitor',
    body: const BodyRule.jsonObject({
      'episodeIds': _nonEmpty,
      'monitored': _statedFlag,
    }),
  ),
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/seasonpass',
    body: const BodyRule.jsonObject({'series': _nonEmpty}),
  ),
  AllowedRequest.write(HttpMethod.delete, 'api/v3/episodefile/{id}'),
]);
