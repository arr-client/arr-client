import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

// What a write may touch: the library and its activity, never configuration.
const _writable = {
  'album',
  'albumstudio',
  'artist',
  'blocklist',
  'command',
  'history',
  'manualimport',
  'queue',
  'release',
  'trackfile',
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
          'includeUnknownArtistItems': ['true'],
        },
      ),
      _send(
        HttpMethod.post,
        'command',
        body: {
          'name': 'AlbumSearch',
          'albumIds': [1],
        },
      ),
      _send(
        HttpMethod.post,
        'command',
        body: {
          'name': 'RescanFolders',
          'folders': ['/music/a'],
          'artistIds': [1],
          'addNewArtists': false,
        },
      ),
      for (final kind in ['artist', 'album'])
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
        {'name': 'RefreshArtist'},
        {'name': 'RefreshArtist', 'artistIds': <int>[]},
        {'name': 'RefreshAlbum'},
        {'name': 'RefreshAlbum', 'albumId': null},
        {'name': 'AlbumSearch', 'albumIds': <int>[]},
        {'name': 'ArtistSearch', 'artistId': null},
        {'name': 'RescanFolders', 'addNewArtists': false},
        {
          'name': 'RescanFolders',
          'artistIds': [1],
          'addNewArtists': false,
        },
        // Left out, the server adds the artists it finds.
        {
          'name': 'RescanFolders',
          'folders': ['/music/a'],
          'artistIds': [1],
        },
      ])
        _send(HttpMethod.post, 'command', body: body),
      _send(HttpMethod.get, 'release'),
      // The default hides the downloads the server cannot match.
      _send(HttpMethod.get, 'queue'),
      // What is deleted never rests on a server default.
      _send(HttpMethod.delete, 'artist/1'),
      _send(
        HttpMethod.delete,
        'album/1',
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
