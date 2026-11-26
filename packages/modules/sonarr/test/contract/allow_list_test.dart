import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

// What a write may touch: the library and its activity, never configuration.
const _writable = {
  'blocklist',
  'command',
  'episode',
  'episodefile',
  'history',
  'manualimport',
  'queue',
  'release',
  'seasonpass',
  'series',
};

ServiceRequest _send(
  HttpMethod method,
  String path, {
  Map<String, List<String>> query = const {},
  Object? body,
}) => ServiceRequest(
  method,
  'api/v3/$path',
  query: query,
  body: body == null ? null : JsonBody(body),
);

void main() {
  test('permits what is listed', () {
    final listed = [
      _send(
        HttpMethod.get,
        'queue',
        query: {
          'includeUnknownSeriesItems': ['true'],
        },
      ),
      _send(
        HttpMethod.post,
        'command',
        body: {
          'name': 'EpisodeSearch',
          'episodeIds': [1],
        },
      ),
    ];
    for (final request in listed) {
      expect(allowList.permits(request), isTrue, reason: request.path);
    }
  });

  test('refuses what is not listed', () {
    final unlisted = [
      for (final path in [
        'config/host',
        'customformat',
        'downloadclient',
        'indexer',
        'notification',
        'qualityprofile',
        'rootfolder',
        'tag',
      ])
        for (final method in [HttpMethod.post, HttpMethod.put])
          _send(method, path, body: <String, Object?>{}),
      _send(HttpMethod.delete, 'rootfolder/1'),
      _send(HttpMethod.put, 'qualitydefinition/1', body: <String, Object?>{}),
      _send(HttpMethod.post, 'system/restart'),
      for (final name in ['ApplicationUpdate', 'Backup', 'RssSync'])
        _send(HttpMethod.post, 'command', body: {'name': name}),
      // Without its series it would refresh the whole library.
      _send(HttpMethod.post, 'command', body: {'name': 'RefreshSeries'}),
      // Hides unmatched downloads.
      _send(HttpMethod.get, 'queue'),
    ];
    for (final request in unlisted) {
      expect(
        allowList.permits(request),
        isFalse,
        reason: '${request.method.name} ${request.path}',
      );
    }
  });

  test('lists no write outside the library and its activity', () {
    for (final entry in allowList.entries) {
      if (entry.method == HttpMethod.get) continue;
      expect(entry.path, startsWith('api/v3/'));
      expect(_writable, contains(entry.path.split('/')[2]), reason: entry.path);
    }
  });
}
