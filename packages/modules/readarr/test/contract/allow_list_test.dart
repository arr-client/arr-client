import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

// What a write may touch: the library and its activity, never configuration.
const _writable = {
  'author',
  'blocklist',
  'book',
  'bookfile',
  'bookshelf',
  'command',
  'history',
  'manualimport',
  'queue',
  'release',
};

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
      _send(
        HttpMethod.get,
        'queue',
        query: {
          'includeUnknownAuthorItems': ['true'],
        },
      ),
      _send(
        HttpMethod.post,
        'command',
        body: {
          'name': 'BookSearch',
          'bookIds': [1],
        },
      ),
      _send(
        HttpMethod.post,
        'command',
        body: {
          'name': 'RescanFolders',
          'folders': ['/books/a'],
          'authorIds': [1],
          'addNewAuthors': false,
        },
      ),
      for (final kind in ['author', 'book'])
        _send(
          HttpMethod.get,
          'mediacover/$kind/1/cover.jpg',
          query: {
            'lastWrite': ['1'],
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
        'config/development',
        'config/host',
        'customformat',
        'downloadclient',
        'indexer',
        'metadataprofile',
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
      // Without their targets these act on the whole library.
      for (final body in <Map<String, Object?>>[
        {'name': 'RefreshAuthor'},
        {'name': 'RefreshAuthor', 'authorId': null},
        {'name': 'RefreshBook'},
        {'name': 'RefreshBook', 'bookId': null},
        {'name': 'BookSearch', 'bookIds': <int>[]},
        {'name': 'AuthorSearch', 'authorId': null},
        {'name': 'RescanFolders', 'addNewAuthors': false},
        {
          'name': 'RescanFolders',
          'authorIds': [1],
          'addNewAuthors': false,
        },
        // Left out, the server adds the authors it finds.
        {
          'name': 'RescanFolders',
          'folders': ['/books/a'],
          'authorIds': [1],
        },
      ])
        _send(HttpMethod.post, 'command', body: body),
      _send(HttpMethod.get, 'release'),
      // The default hides the downloads the server cannot match.
      _send(HttpMethod.get, 'queue'),
      // What is deleted never rests on a server default.
      _send(HttpMethod.delete, 'author/1'),
      _send(
        HttpMethod.delete,
        'book/1',
        query: {
          'deleteFiles': ['false'],
        },
      ),
      // A grab that names anything else could download as something else.
      _send(
        HttpMethod.post,
        'release',
        body: {'guid': 'g', 'indexerId': 1, 'downloadClientId': 2},
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

  test('every write is to the library or its activity', () {
    for (final entry in allowList.entries) {
      if (entry.method == HttpMethod.get) continue;
      expect(entry.path, startsWith('api/v1/'));
      expect(_writable, contains(entry.path.split('/')[2]), reason: entry.path);
    }
  });
}
