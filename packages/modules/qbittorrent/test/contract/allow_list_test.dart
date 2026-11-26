// The app changes nothing in a download client (FR-019, FR-031, spec story 7).

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

const _credentials = {'username': 'u', 'password': 'p'};

ServiceRequest _request(
  HttpMethod method,
  String path, {
  Map<String, List<String>> query = const {},
  RequestBody? body,
}) => ServiceRequest(method, 'api/v2/$path', query: query, body: body);

void main() {
  test('permits the reads and the login', () {
    final listed = [
      _request(HttpMethod.get, 'app/version'),
      _request(HttpMethod.get, 'app/webapiVersion'),
      _request(HttpMethod.get, 'torrents/info'),
      _request(
        HttpMethod.post,
        'auth/login',
        body: const FormBody(_credentials),
      ),
    ];
    for (final request in listed) {
      expect(allowList.permits(request), isTrue, reason: request.path);
    }
  });

  test('refuses everything that changes the client', () {
    // qBittorrent also takes some of these as a GET with a query.
    final writes = [
      'app/deleteAPIKey',
      'app/rotateAPIKey',
      'app/setPreferences',
      'app/shutdown',
      'auth/logout',
      'torrents/add',
      'torrents/delete',
      'torrents/pause',
      'torrents/recheck',
      'torrents/resume',
      'torrents/setCategory',
      'torrents/setDownloadLimit',
      'torrents/setForceStart',
      'torrents/start',
      'torrents/stop',
      'transfer/setDownloadLimit',
      'transfer/toggleSpeedLimitsMode',
    ];
    final unlisted = [
      for (final path in writes) ...[
        _request(HttpMethod.get, path),
        _request(HttpMethod.post, path),
        _request(
          HttpMethod.post,
          path,
          body: const FormBody({'hashes': 'all'}),
        ),
      ],
      _request(HttpMethod.post, 'torrents/info'),
      _request(HttpMethod.delete, 'torrents/info'),
      // Configuration, which the app does not read either.
      _request(HttpMethod.get, 'app/preferences'),
      _request(
        HttpMethod.get,
        'torrents/info',
        query: {
          'hashes': ['abc'],
        },
      ),
      // A password does not go into an address.
      _request(
        HttpMethod.get,
        'auth/login',
        query: {
          'username': ['u'],
          'password': ['p'],
        },
      ),
      _request(HttpMethod.post, 'auth/login'),
      _request(
        HttpMethod.post,
        'auth/login',
        body: const JsonBody(_credentials),
      ),
      _request(
        HttpMethod.post,
        'auth/login',
        body: const FormBody({..._credentials, 'json': '{}'}),
      ),
    ];
    for (final request in unlisted) {
      expect(
        allowList.permits(request),
        isFalse,
        reason: '${request.method.name} ${request.path}',
      );
    }
  });

  test('lists nothing but reads and the login', () {
    for (final entry in allowList.entries) {
      switch (entry.requestClass) {
        case RequestClass.read:
          expect(entry.method, HttpMethod.get, reason: entry.path);
        case RequestClass.authentication:
          expect(entry.path, 'api/v2/auth/login');
        case RequestClass.write:
          fail('A write is listed: ${entry.path}');
      }
    }
  });
}
