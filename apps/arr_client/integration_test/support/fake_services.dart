/// How the fake servers answer as the services do. Each knows only what the
/// tests use; a test that needs more adds it to [FakeServarr.answers], by path.
library;

import 'fake_server.dart';

/// A service of the Servarr family, which refuses any other [apiKey].
class FakeServarr {
  FakeServarr({
    required this.appName,
    required this.apiKey,
    required this.version,
    Map<String, Object?>? answers,
  }) : answers = {...?answers};

  final String appName;

  /// Changed, as when the key is renewed on the server.
  String apiKey;

  final String version;

  /// The JSON of a GET, by the path after `/api/v3/`.
  final Map<String, Object?> answers;

  Reply call(ReceivedRequest request) {
    if (request.headers['x-api-key'] != apiKey) return const Reply(401);
    const base = '/api/v3/';
    if (request.method != 'GET' || !request.path.startsWith(base)) {
      return const Reply(404);
    }
    final path = request.path.substring(base.length);
    if (path == 'system/status') {
      return Reply.json({'appName': appName, 'version': version});
    }
    if (answers.containsKey(path)) return Reply.json(answers[path]);
    return const Reply(404);
  }
}

/// A page of a paged resource that holds all of [records].
Map<String, Object?> page(List<Object?> records) => {
  'page': 1,
  'pageSize': 250,
  'totalRecords': records.length,
  'records': records,
};

/// A Radarr with the movies titled [movies] and the downloads [queue].
FakeServarr fakeRadarr({
  required String apiKey,
  String version = '5.20.0.1000',
  List<String> movies = const [],
  List<Map<String, Object?>> queue = const [],
}) => FakeServarr(
  appName: 'Radarr',
  apiKey: apiKey,
  version: version,
  answers: {
    'movie': [
      for (final (index, title) in movies.indexed)
        {
          'id': index + 1,
          'title': title,
          'sortTitle': title.toLowerCase(),
          'year': 2020,
          'monitored': true,
          'hasFile': true,
          'isAvailable': true,
        },
    ],
    'queue': page(queue),
    'queue/details': queue,
    'history': page(const []),
    'qualityprofile': const <Object?>[],
    'tag': const <Object?>[],
    'health': const <Object?>[],
  },
);

/// A download of the first movie, half done.
Map<String, Object?> halfDoneDownload(String title) => {
  'id': 1,
  'movieId': 1,
  'title': title,
  'status': 'downloading',
  'trackedDownloadStatus': 'ok',
  'trackedDownloadState': 'downloading',
  'size': 2000000000,
  'sizeleft': 1000000000,
  'protocol': 'torrent',
};

/// A Sonarr without series.
FakeServarr fakeSonarr({
  required String apiKey,
  String version = '4.0.9.2000',
}) => FakeServarr(
  appName: 'Sonarr',
  apiKey: apiKey,
  version: version,
  answers: {
    'series': const <Object?>[],
    'queue': page(const []),
    'queue/details': const <Object?>[],
    'history': page(const []),
    'calendar': const <Object?>[],
    'qualityprofile': const <Object?>[],
    'tag': const <Object?>[],
    'health': const <Object?>[],
  },
);

/// A qBittorrent 5.3.1 that takes [apiKey], which qBittorrent refuses with 403.
Handler fakeQbittorrent({required String apiKey}) => (request) {
  if (request.headers['authorization'] != 'Bearer $apiKey') {
    return const Reply(403);
  }
  if (request.path == '/api/v2/app/version') {
    return const Reply(200, body: 'v5.3.1');
  }
  return const Reply(404);
};
