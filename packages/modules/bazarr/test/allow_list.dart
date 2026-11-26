/// Every request the Bazarr module may make (FR-019), from
/// specs/001-arr-companion-app/contracts/upstream-apis.md, with parameters
/// placed as Bazarr's web UI places them: the ids of the media in the query,
/// everything else of a write in a form. Adapter tests run through it.
///
/// Anything not here is refused, every configuration write included.
/// `system/settings` is not even read: it holds the keys of every connected
/// service.
library;

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';

const _any = ParamRule.any();
const _id = ParamRule.nonEmpty();

// Bazarr capitalizes these before it reads them.
const _flag = ParamRule.only({'True', 'False', 'true', 'false'});

// `PATCH subtitles` compares them with "True" as they stand.
const _exactFlag = ParamRule.only({'True', 'False'});

const _page = {'start': _any, 'length': _any};

const _episode = {'seriesid': _id, 'episodeid': _id};
const _movie = {'radarrid': _id};

// A language to search for.
const _language = {'language': _id, 'forced': _flag, 'hi': _flag};

// A candidate of a manual search, sent back. 1.5 gives the format as a number.
const _candidate = {
  'hi': _flag,
  'forced': _flag,
  'original_format': ParamRule.only({'True', 'False', '0', '1'}),
  'provider': _id,
  'subtitle': _id,
};

/// The Bazarr allow-list.
final allowList = AllowList([
  AllowedRequest.read('api/system/status'),
  AllowedRequest.read('api/series', query: {..._page, 'seriesid[]': _any}),
  AllowedRequest.read('api/movies', query: {..._page, 'radarrid[]': _any}),
  AllowedRequest.read(
    'api/episodes',
    query: {'seriesid[]': _any, 'episodeid[]': _any},
  ),
  for (final path in [
    'episodes/wanted',
    'movies/wanted',
    'episodes/history',
    'movies/history',
  ])
    AllowedRequest.read('api/$path', query: _page),
  AllowedRequest.read('api/providers/episodes', query: {'episodeid': _id}),
  AllowedRequest.read('api/providers/movies', query: {'radarrid': _id}),
  for (final (path, ids) in [('episodes', _episode), ('movies', _movie)]) ...[
    AllowedRequest.write(
      HttpMethod.patch,
      'api/$path/subtitles',
      query: ids,
      body: const BodyRule.form(_language),
    ),
    AllowedRequest.write(
      HttpMethod.delete,
      'api/$path/subtitles',
      query: ids,
      body: const BodyRule.form({..._language, 'path': _id}),
    ),
    AllowedRequest.write(
      HttpMethod.post,
      'api/providers/$path',
      query: ids,
      body: const BodyRule.form(_candidate),
    ),
  ],
  // The same path also translates, extracts and rewrites subtitles.
  AllowedRequest.write(
    HttpMethod.patch,
    'api/subtitles',
    query: {
      'action': const ParamRule.only({'sync'}),
    },
    body: const BodyRule.form({
      'type': ParamRule.only({'episode', 'movie'}),
      'id': _id,
      'language': _id,
      'path': _id,
      'forced': _exactFlag,
      'hi': _exactFlag,
    }),
  ),
]);
