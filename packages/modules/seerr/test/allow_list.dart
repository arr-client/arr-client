/// Every request the Seerr module may make (FR-019), from
/// specs/001-arr-companion-app/contracts/upstream-apis.md, for Seerr,
/// Overseerr and Jellyseerr. Adapter tests run through it.
///
/// The reads include the ones made only to be given a CSRF token (research
/// R18): there is no request of its own for that.
library;

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';

const _any = ParamRule.any();
const _required = ParamRule.any(required: true);
const _text = ParamRule.nonEmpty();
const _paging = {'take': _required, 'skip': _required};
const _page = {'page': _any};

AllowedRequest _read(String path, {Map<String, ParamRule> query = const {}}) =>
    AllowedRequest.read('api/v1/$path', query: query);

AllowedRequest _write(
  String path, {
  HttpMethod method = HttpMethod.post,
  BodyRule body = const BodyRule.none(),
}) => AllowedRequest.write(method, 'api/v1/$path', body: body);

AllowedRequest _auth(String path, {BodyRule body = const BodyRule.none()}) =>
    AllowedRequest.authentication(HttpMethod.post, 'api/v1/$path', body: body);

/// The Seerr allow-list.
final allowList = AllowList([
  // Posters, outside the API (research R10).
  AllowedRequest.read('imageproxy/**'),
  _read('auth/me'),
  _read('status'),
  _read('settings/public'),
  _read('search', query: {'query': _text, ..._page}),
  _read('discover/{trending|movies|tv}', query: _page),
  _read('discover/{movies|tv}/upcoming', query: _page),
  _read('movie/{id}'),
  _read('tv/{id}'),
  _read('tv/{id}/season/{n}'),
  _read('user/{id}/quota'),
  _read('request', query: {..._paging, 'filter': _any, 'sort': _any}),
  _read('request/count'),
  _read('issue', query: {..._paging, 'filter': _any, 'sort': _any}),
  _read('issue/{id}'),
  // A request names a title and a variant. Server, profile, folder, user and
  // quota options are not sent.
  _write(
    'request',
    body: const BodyRule.jsonObject({
      'mediaType': ParamRule.only({'movie', 'tv'}),
      'mediaId': _required,
      'is4k': ParamRule.only({'true', 'false'}),
      'seasons': _any,
      'tvdbId': _any,
    }, closed: true),
  ),
  _write('request/{id}', method: HttpMethod.delete),
  _write('request/{id}/{approve|decline}'),
  _write('request/{id}/retry'),
  _write(
    'issue',
    body: const BodyRule.jsonObject({
      'issueType': ParamRule.only({'1', '2', '3', '4'}),
      'message': _text,
      'mediaId': _required,
    }, closed: true),
  ),
  _write(
    'issue/{id}/comment',
    body: const BodyRule.jsonObject({'message': _text}, closed: true),
  ),
  _write('issue/{id}/{open|resolved}'),
  _auth(
    'auth/local',
    body: const BodyRule.jsonObject({
      'email': _text,
      'password': _text,
    }, closed: true),
  ),
  // No host name: that is how the server is first set up.
  _auth(
    'auth/jellyfin',
    body: const BodyRule.jsonObject({
      'username': _text,
      'password': _text,
    }, closed: true),
  ),
  _auth('auth/logout'),
]);
