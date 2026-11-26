/// Every request the Lidarr module may make (FR-019), from
/// specs/001-arr-companion-app/contracts/upstream-apis.md, with paths and
/// parameter names as in Lidarr's v1 API. Adapter tests run through it.
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

// Records embed these only when asked.
const _embedded = {'includeArtist': _flag, 'includeAlbum': _flag};

const _queueRemoval = {
  // The server removes from the download client unless told not to.
  'removeFromClient': _statedFlag,
  'blocklist': _statedFlag,
  'skipRedownload': _flag,
};

// Both stated: what is deleted never rests on a server default.
const _deletion = {
  'deleteFiles': _statedFlag,
  'addImportListExclusion': _statedFlag,
};

const _ids = BodyRule.jsonObject({'ids': _nonEmpty});

/// `POST command` with one command name. The server runs any command it knows,
/// and some act on the whole library when [targets] are left out.
AllowedRequest _command(
  String name,
  List<String> targets, {
  Map<String, ParamRule> fields = const {},
}) => AllowedRequest.write(
  HttpMethod.post,
  'api/v1/command',
  body: BodyRule.jsonObject({
    'name': ParamRule.only({name}),
    for (final target in targets) target: _nonEmpty,
    ...fields,
  }),
);

/// The Lidarr allow-list.
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
    AllowedRequest.read('api/v1/$path'),
  AllowedRequest.read(
    'api/v1/calendar',
    query: {
      'start': _any,
      'end': _any,
      'unmonitored': _flag,
      'includeArtist': _flag,
      'tags': _any,
    },
  ),
  AllowedRequest.read(
    'api/v1/history',
    query: {
      ..._paging,
      ..._embedded,
      'includeTrack': _flag,
      'eventType': _any,
      'albumId': _any,
      'downloadId': _any,
      'artistIds': _any,
      'quality': _any,
    },
  ),
  AllowedRequest.read(
    'api/v1/history/since',
    query: {
      'date': _nonEmpty,
      'eventType': _any,
      ..._embedded,
      'includeTrack': _flag,
    },
  ),
  for (final list in ['missing', 'cutoff'])
    AllowedRequest.read(
      'api/v1/wanted/$list',
      query: {..._paging, 'includeArtist': _flag, 'monitored': _flag},
    ),
  AllowedRequest.read(
    'api/v1/queue',
    query: {
      ..._paging,
      ..._embedded,
      // The default hides downloads the server cannot match.
      'includeUnknownArtistItems': const ParamRule.only({'true'}),
      'artistIds': _any,
      'protocol': _any,
      'quality': _any,
    },
  ),
  // Has no include-unknown flag: it returns unmatched downloads too.
  AllowedRequest.read(
    'api/v1/queue/details',
    query: {'artistId': _any, 'albumIds': _any, ..._embedded},
  ),
  AllowedRequest.read('api/v1/blocklist', query: {..._paging}),
  // An album or an artist: without either the server answers with its RSS
  // feeds instead.
  AllowedRequest.read('api/v1/release', query: {'albumId': _nonEmpty}),
  AllowedRequest.read('api/v1/release', query: {'artistId': _nonEmpty}),
  AllowedRequest.read('api/v1/command/{id}'),
  AllowedRequest.read(
    'api/v1/manualimport',
    query: {
      'folder': _any,
      'downloadId': _any,
      'artistId': _any,
      'filterExistingFiles': _flag,
      'replaceExistingFiles': _flag,
    },
  ),
  // The cache buster of the image addresses the server returns.
  AllowedRequest.read(
    'api/v1/mediacover/{artist|album}/{id}/**',
    query: {'lastWrite': _any},
  ),

  // Library, lookup and item history.
  AllowedRequest.read('api/v1/artist', query: {'mbId': _any}),
  AllowedRequest.read('api/v1/artist/{id}'),
  AllowedRequest.read(
    'api/v1/album',
    query: {
      'artistId': _any,
      'albumIds': _any,
      'foreignAlbumId': _any,
      'includeAllArtistAlbums': _flag,
    },
  ),
  AllowedRequest.read('api/v1/album/{id}'),
  AllowedRequest.read(
    'api/v1/track',
    query: {
      'artistId': _any,
      'albumId': _any,
      'albumReleaseId': _any,
      'trackIds': _any,
    },
  ),
  AllowedRequest.read(
    'api/v1/trackfile',
    query: {'artistId': _any, 'albumId': _any, 'trackFileIds': _any},
  ),
  AllowedRequest.read('api/v1/metadataprofile'),
  AllowedRequest.read('api/v1/artist/lookup', query: {'term': _nonEmpty}),
  AllowedRequest.read('api/v1/album/lookup', query: {'term': _nonEmpty}),
  AllowedRequest.read(
    'api/v1/history/artist',
    query: {
      'artistId': _nonEmpty,
      'albumId': _any,
      'eventType': _any,
      ..._embedded,
      'includeTrack': _flag,
    },
  ),

  // Queue, history, releases and blocklist.
  AllowedRequest.write(
    HttpMethod.delete,
    'api/v1/queue/{id}',
    query: _queueRemoval,
  ),
  AllowedRequest.write(
    HttpMethod.delete,
    'api/v1/queue/bulk',
    query: _queueRemoval,
    body: _ids,
  ),
  AllowedRequest.write(HttpMethod.post, 'api/v1/queue/grab/{id}'),
  AllowedRequest.write(HttpMethod.post, 'api/v1/history/failed/{id}'),
  // A grab names the release; for one the server could not match, also what
  // was searched for. Any further field could make it download as something
  // else.
  for (final target in const <List<String>>[
    [],
    ['albumId'],
    ['artistId'],
  ])
    AllowedRequest.write(
      HttpMethod.post,
      'api/v1/release',
      body: BodyRule.jsonObject({
        'guid': _nonEmpty,
        'indexerId': _nonEmpty,
        for (final field in target) field: _nonEmpty,
      }, closed: true),
    ),
  AllowedRequest.write(HttpMethod.delete, 'api/v1/blocklist/{id}'),
  AllowedRequest.write(HttpMethod.delete, 'api/v1/blocklist/bulk', body: _ids),

  // Commands and manual import.
  _command('AlbumSearch', ['albumIds']),
  _command('ArtistSearch', ['artistId']),
  _command('RefreshArtist', ['artistIds']),
  _command('RefreshAlbum', ['albumId']),
  // Without its folders it scans every root folder, and unless told not to it
  // adds the artists it finds there.
  _command(
    'RescanFolders',
    ['folders', 'artistIds'],
    fields: const {
      'addNewArtists': ParamRule.only({'false'}),
    },
  ),
  _command('ManualImport', ['files']),
  // Takes a list of candidates.
  AllowedRequest.write(
    HttpMethod.post,
    'api/v1/manualimport',
    body: const BodyRule.json(),
  ),

  // Add, edit and delete.
  for (final kind in ['artist', 'album']) ...[
    AllowedRequest.write(
      HttpMethod.post,
      'api/v1/$kind',
      body: const BodyRule.jsonObject({}),
    ),
    AllowedRequest.write(
      HttpMethod.put,
      'api/v1/$kind/{id}',
      body: const BodyRule.jsonObject({}),
    ),
    AllowedRequest.write(
      HttpMethod.delete,
      'api/v1/$kind/{id}',
      query: _deletion,
    ),
  ],
  AllowedRequest.write(
    HttpMethod.put,
    'api/v1/artist/editor',
    body: const BodyRule.jsonObject({'artistIds': _nonEmpty}),
  ),

  // Monitoring, monitoring option and file delete.
  AllowedRequest.write(
    HttpMethod.put,
    'api/v1/album/monitor',
    body: const BodyRule.jsonObject({
      'albumIds': _nonEmpty,
      'monitored': _statedFlag,
    }),
  ),
  AllowedRequest.write(
    HttpMethod.post,
    'api/v1/albumstudio',
    body: const BodyRule.jsonObject({'artist': _nonEmpty}),
  ),
  AllowedRequest.write(HttpMethod.delete, 'api/v1/trackfile/{id}'),
]);
