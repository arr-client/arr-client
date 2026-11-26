import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

ServiceRequest _send(
  HttpMethod method,
  String path, {
  Map<String, List<String>> query = const {},
  Object? body,
}) => ServiceRequest(
  method,
  'api/v1/$path',
  query: query,
  body: body == null ? null : JsonBody(body),
);

void main() {
  test('permits what is listed', () {
    final listed = [
      for (final path in [
        'system/status',
        'health',
        'indexer',
        'indexer/categories',
        'indexerstatus',
      ])
        _send(HttpMethod.get, path),
      _send(
        HttpMethod.get,
        'search',
        query: {
          'query': ['sintel'],
          'type': ['search'],
          'categories': ['2000', '5000'],
          'indexerIds': ['1', '2'],
        },
      ),
      _send(HttpMethod.post, 'search', body: {'guid': 'g', 'indexerId': 1}),
    ];
    for (final request in listed) {
      expect(allowList.permits(request), isTrue, reason: request.path);
    }
  });

  test('refuses what is not listed', () {
    final unlisted = [
      for (final path in [
        'applications',
        'appprofile',
        'config/host',
        'downloadclient',
        'indexer',
        'indexerproxy',
        'notification',
        'tag',
        'command',
      ])
        for (final method in [HttpMethod.post, HttpMethod.put])
          _send(method, path, body: <String, Object?>{}),
      _send(HttpMethod.delete, 'indexer/1'),
      _send(HttpMethod.get, 'indexer/1'),
      _send(HttpMethod.get, 'config/host'),
      _send(HttpMethod.get, 'downloadclient'),
      // The server's log holds the addresses it asked.
      _send(HttpMethod.get, 'log'),
      // Without a term the server answers with its indexers' feeds.
      _send(HttpMethod.get, 'search'),
      _send(
        HttpMethod.get,
        'search',
        query: {
          'query': [' '],
        },
      ),
      // Several releases at once, which the app does not grab.
      _send(HttpMethod.post, 'search/bulk', body: <Object>[]),
      _send(HttpMethod.post, 'search', body: <String, Object?>{}),
      _send(HttpMethod.post, 'search', body: {'guid': 'g'}),
      _send(HttpMethod.post, 'search', body: {'guid': '', 'indexerId': 1}),
      for (final further in ['downloadUrl', 'magnetUrl', 'downloadClientId'])
        _send(
          HttpMethod.post,
          'search',
          body: {'guid': 'g', 'indexerId': 1, further: 1},
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

  test('lists one write, the grab', () {
    final writes = allowList.entries.where((e) => e.method != HttpMethod.get);
    expect(writes.map((e) => (e.method, e.path)), [
      (HttpMethod.post, 'api/v1/search'),
    ]);
  });
}
