// Only the requests of contracts/upstream-apis.md may be made (FR-019).

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

ServiceRequest _request(
  HttpMethod method,
  String path, {
  Map<String, List<String>> query = const {},
  Object? body,
}) => ServiceRequest(
  method,
  path,
  query: query,
  body: body == null ? null : JsonBody(body),
);

ServiceRequest _get(
  String path, {
  Map<String, List<String>> query = const {},
}) => _request(HttpMethod.get, 'api/v1/$path', query: query);

ServiceRequest _post(String path, [Object? body]) =>
    _request(HttpMethod.post, 'api/v1/$path', body: body);

const _paging = {
  'take': ['20'],
  'skip': ['0'],
};

const _movie = {'mediaType': 'movie', 'mediaId': 19, 'is4k': false};

void main() {
  test('permits what the contract lists', () {
    final listed = [
      _request(HttpMethod.get, 'imageproxy/tmdb/t/p/w500/poster.jpg'),
      _request(HttpMethod.get, 'imageproxy/t/p/w500/poster.jpg'),
      _get('auth/me'),
      _get('status'),
      _get('settings/public'),
      _get(
        'search',
        query: {
          'query': ['a'],
          'page': ['2'],
        },
      ),
      _get('discover/trending'),
      _get('discover/movies'),
      _get('discover/tv'),
      _get('discover/movies/upcoming'),
      _get('discover/tv/upcoming'),
      _get('movie/19'),
      _get('tv/1100'),
      _get('tv/1100/season/1'),
      _get('user/2/quota'),
      _get('request', query: _paging),
      _get('request/count'),
      _get('issue', query: _paging),
      _get('issue/4'),
      _post('request', _movie),
      _post('request', {
        'mediaType': 'tv',
        'mediaId': 1100,
        'is4k': true,
        'seasons': [1, 2],
      }),
      _request(HttpMethod.delete, 'api/v1/request/9'),
      _post('request/9/approve'),
      _post('request/9/decline'),
      _post('request/9/retry'),
      _post('issue', {'issueType': 1, 'message': 'a', 'mediaId': 9}),
      _post('issue/4/comment', {'message': 'a'}),
      _post('issue/4/open'),
      _post('issue/4/resolved'),
      _post('auth/local', {'email': 'a@b.test', 'password': 'p'}),
      _post('auth/jellyfin', {'username': 'a', 'password': 'p'}),
      _post('auth/logout'),
    ];
    for (final request in listed) {
      expect(allowList.permits(request), isTrue, reason: request.path);
    }
  });

  test('refuses what changes configuration, users or media', () {
    final unlisted = [
      _get('settings/main'),
      _get('settings/radarr'),
      _post('settings/main', {'cacheImages': true}),
      _post('settings/network', {'csrfProtection': false}),
      _get('user'),
      _post('user', {'email': 'a@b.test'}),
      _post('user/2/settings/permissions', {'permissions': 2}),
      _post('media/9/available', {'is4k': false}),
      _request(HttpMethod.delete, 'api/v1/media/9'),
      _post('blocklist', {'tmdbId': 1}),
      _request(HttpMethod.put, 'api/v1/request/9', body: _movie),
      _post('request/9/pending'),
      _request(HttpMethod.delete, 'api/v1/issue/4'),
      _post('request', {..._movie, 'userId': 1}),
      _post('request', {..._movie, 'serverId': 0}),
      _post('request', {..._movie, 'profileId': 4}),
      _post('request', {..._movie, 'rootFolder': '/x'}),
      _post('request', {..._movie, 'ignoreQuota': true}),
      _post('issue', {
        'issueType': 1,
        'message': 'a',
        'mediaId': 9,
        'userId': 1,
      }),
      _post('auth/jellyfin', {
        'username': 'a',
        'password': 'p',
        'hostname': 'x',
      }),
      _post('auth/plex', {'authToken': 't'}),
      _post('auth/reset-password', {'email': 'a@b.test'}),
    ];
    for (final request in unlisted) {
      expect(
        allowList.permits(request),
        isFalse,
        reason: '${request.method.name} ${request.path}',
      );
    }
  });

  test('writes nothing but requests and issues', () {
    for (final entry in allowList.entries) {
      switch (entry.requestClass) {
        case RequestClass.read:
          expect(entry.method, HttpMethod.get, reason: entry.path);
        case RequestClass.authentication:
          expect(entry.path, startsWith('api/v1/auth/'));
        case RequestClass.write:
          expect(entry.path, matches(RegExp(r'^api/v1/(request|issue)\b')));
      }
    }
  });
}
