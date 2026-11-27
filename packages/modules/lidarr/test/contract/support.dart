// A Lidarr and a cache to run the module's adapters against. The tests go
// through `LidarrModule().capability<T>`, so they fix what the module does and
// not how it is divided up.
//
// The fixtures were recorded from a throwaway Lidarr 3.1.6.5079 in the dev
// stack's image, with qBittorrent as its download client, a made-up Torznab
// indexer and silent audio files, and passed tool/sanitize_fixture.dart. Before
// that, long lists that nothing reads were cut down: links, genres, the other
// releases of an album, some tracks, files, albums and import events. So counts
// do not add up to the statistics.
//
// The server held two artists. Artist 1, monitored, has three albums: album 1
// with three of its tracks imported by hand, album 2 complete in a quality
// below the profile's cutoff, and album 3 without files. Artist 2 is not
// monitored and was made by adding one of its albums, album 4. The queue was
// recorded before the manual import of album 1, with a download that could not
// be imported and one that no artist matches.
//
// Titles, names, paths and MusicBrainz ids are placeholders, the same one for
// equal values. What the tests need beyond the recordings they change here.
//
// The server answers as the recorded one did: embedded artists and albums only
// where asked for (albums of `album` always name their artist), an empty list
// for the albums and tracks of an artist or album it does not have, and 404 for
// such an artist, album, command or file list.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidarr/lidarr_module.dart';

import '../allow_list.dart';

const instanceId = 'i1';

/// The version the fixtures were recorded from.
const recordedVersion = '3.1.6.5079';

Object? _decode(String name) => jsonDecode(
  File('test/fixtures/$recordedVersion/$name.json').readAsStringSync(),
);

/// A fresh copy of a recorded list.
List<Map<String, Object?>> records(String name) =>
    (_decode(name)! as List<Object?>).cast<Map<String, Object?>>();

/// A fresh copy of a recorded object.
Map<String, Object?> record(String name) =>
    _decode(name)! as Map<String, Object?>;

/// A fresh copy of the records of a recorded page.
List<Map<String, Object?>> pageRecords(String name) =>
    (record(name)['records']! as List<Object?>).cast<Map<String, Object?>>();

/// The one of [list] with [id].
Map<String, Object?> byId(List<Map<String, Object?>> list, int id) =>
    list.singleWhere((record) => record['id'] == id);

ItemRef artistRef(int id) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.artist, remoteId: id);

ItemRef albumRef(int id) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.album, remoteId: id);

ItemRef trackRef(int id) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.track, remoteId: id);

MediaTarget artist([int id = 1]) => MediaTarget(artistRef(id));

MediaTarget album([int id = 1]) => MediaTarget(albumRef(id));

MediaTarget track([int id = 1]) => MediaTarget(trackRef(id));

/// A target that is not Lidarr's.
const movie = MediaTarget(
  ItemRef(instanceId: instanceId, kind: MediaKind.movie, remoteId: 1),
);

/// Artist 1 of some other instance, whose id names another artist here.
const elsewhere = ItemRef(
  instanceId: 'i2',
  kind: MediaKind.artist,
  remoteId: 1,
);

/// The messages the core's client takes from a refusal.
List<String> _messages(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  return [
    if (json is List<Object?>)
      for (final entry in json)
        if (entry case {'errorMessage': final String message}) message,
    if (json case {'message': final String message}) message,
  ];
}

Result<ServiceResponse, HttpError> _answer(
  int status,
  String body, {
  String contentType = 'application/json; charset=utf-8',
  bool write = false,
}) {
  final response = ServiceResponse(
    statusCode: status,
    headers: {
      'content-type': [contentType],
    },
    bytes: Uint8List.fromList(utf8.encode(body)),
  );
  // As the core's client classifies them.
  final failure = switch (status) {
    >= 200 && < 300 when contentType.startsWith('text/html') =>
      const ProxyInterception(),
    >= 200 && < 300 => null,
    400 || 422 => Validation(_messages(body)),
    401 => const AuthFailed(),
    403 => const Forbidden(),
    404 => const NotFound(),
    409 => const Conflict(),
    502 || 504 when write => const OutcomeUnknown(),
    _ => ServerError(statusCode: status),
  };
  return failure == null
      ? Ok(response)
      : Err(HttpError(failure, response: response));
}

/// The recorded answer to each command.
const commandFixtures = {
  'AlbumSearch': 'manage_command_search_album',
  'ArtistSearch': 'manage_command_search_artist',
  'RefreshArtist': 'manage_command_refresh_artist',
  'RefreshAlbum': 'manage_command_refresh_album',
  'RescanFolders': 'manage_command_rescan',
  'ManualImport': 'activity_command_manualimport',
};

/// Answers reads from the recorded lists, which a test may change, and takes
/// the module's writes without changing them. As with the core's client,
/// nothing is sent twice.
class FakeLidarr implements ServiceHttpClient {
  final artists = records('artist');
  final albums = [...records('album_artist_1'), ...records('album_artist_2')];
  final tracks = [...records('track_album_1'), ...records('track_album_2')];
  final trackFiles = [
    ...records('trackfile_album_1'),
    ...records('trackfile_album_2'),
  ];
  final queue = pageRecords('activity_queue');

  /// Newest first.
  final history = pageRecords('activity_history');

  /// What `history/since` has, in the server's order.
  final historySince = records('activity_history_since');
  final blocklist = pageRecords('activity_blocklist');
  final calendar = records('overview_calendar');
  final wantedMissing = pageRecords('overview_wanted_missing');
  final wantedCutoff = pageRecords('overview_wanted_cutoff');
  final qualityProfiles = records('qualityprofile');
  final metadataProfiles = records('metadataprofile');
  final rootFolders = records('rootfolder');
  final tags = records('tag');
  List<Map<String, Object?>> health = records('overview_health');
  List<Map<String, Object?>> diskSpace = records('overview_diskspace');
  List<Map<String, Object?>> manualImport = records('activity_manualimport');
  List<Map<String, Object?>> reprocessed = records(
    'activity_manualimport_reprocess',
  );

  /// What a search for [searchTerm] finds.
  final artistLookup = records('artist_lookup');
  final albumLookup = records('album_lookup');
  static const searchTerm = 'portishead';

  /// What `lidarr:<MusicBrainz id>` can find, beside the searches.
  final artistsById = [
    ...records('artist_lookup_existing'),
    ...records('artist_lookup_new'),
  ];
  final albumsById = records('album_lookup_new');

  /// What `GET command/{id}` answers.
  Map<String, Object?> command = record('manage_command_status');

  /// The id given to an artist or album that is added.
  static const addedId = 42;

  final requests = <ServiceRequest>[];

  /// If set, every request gets this.
  Result<ServiceResponse, HttpError>? always;

  /// If set, every write gets this.
  Result<ServiceResponse, HttpError>? writeAnswer;

  /// Answers for single paths of reads, below `api/v1/`.
  final overrides = <String, Result<ServiceResponse, HttpError>>{};

  /// No answer from the address, from now on.
  void goOffline() => always = const Err(HttpError(Unreachable()));

  /// The requests that were not reads.
  Iterable<ServiceRequest> get writes =>
      requests.where((request) => request.method != HttpMethod.get);

  /// An answer with [body] as it is; [write] if it answers one.
  static Result<ServiceResponse, HttpError> body(
    String body, {
    int status = 200,
    String contentType = 'application/json; charset=utf-8',
    bool write = false,
  }) => _answer(status, body, contentType: contentType, write: write);

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    requests.add(request);
    expect(request.path, startsWith('api/v1/'));
    final path = request.path.substring('api/v1/'.length);
    if (request.method != HttpMethod.get) {
      return always ?? writeAnswer ?? _written(request, path);
    }
    return always ?? overrides[path] ?? _read(path, request.query);
  }

  Result<ServiceResponse, HttpError> _written(
    ServiceRequest request,
    String path,
  ) {
    Result<ServiceResponse, HttpError> ok(String body, [int status = 200]) =>
        _answer(status, body, write: true);

    switch ((request.method, path)) {
      case (HttpMethod.post, 'artist'):
        return _add(
          request,
          artists,
          field: 'foreignArtistId',
          added: 'artist_add',
          exists: 'artist_add_exists',
        );
      case (HttpMethod.post, 'album'):
        return _add(
          request,
          albums,
          field: 'foreignAlbumId',
          added: 'album_add',
          exists: 'album_add_exists',
        );
      case (HttpMethod.post, 'command'):
        final name = (sentBody(request)! as Map<String, Object?>)['name'];
        return ok(jsonEncode(record(commandFixtures[name]!)), 201);
      case (HttpMethod.post, 'release'):
        return ok(jsonEncode(sentBody(request)));
      case (HttpMethod.post, 'manualimport'):
        // Only the files that were sent.
        final paths = {
          for (final file in sentBody(request)! as List<Object?>)
            (file! as Map<String, Object?>)['path'],
        };
        return ok(
          jsonEncode([
            for (final file in reprocessed)
              if (paths.contains(file['path'])) file,
          ]),
          202,
        );
      case (HttpMethod.post, 'albumstudio'):
        return ok('{}', 202);
      case (HttpMethod.put, 'album/monitor' || 'artist/editor'):
        return ok('[]', 202);
      case (HttpMethod.delete, 'queue/bulk' || 'blocklist/bulk'):
        return ok('{}');
    }
    final known = switch (request.method) {
      HttpMethod.put => RegExp(r'^(artist|album)/\d+$'),
      HttpMethod.delete => RegExp(
        r'^(artist|album|trackfile|queue|blocklist)/\d+$',
      ),
      HttpMethod.post => RegExp(r'^(queue/grab|history/failed)/\d+$'),
      _ => null,
    };
    if (known == null || !known.hasMatch(path)) {
      fail('not a write of the module: ${request.method.name} $path');
    }
    return ok('', request.method == HttpMethod.put ? 202 : 200);
  }

  Result<ServiceResponse, HttpError> _add(
    ServiceRequest request,
    List<Map<String, Object?>> held, {
    required String field,
    required String added,
    required String exists,
  }) {
    final sent = sentBody(request)! as Map<String, Object?>;
    if (held.any((item) => item[field] == sent[field])) {
      return _answer(400, jsonEncode(records(exists)), write: true);
    }
    return _answer(
      201,
      jsonEncode({...record(added), field: sent[field], 'id': addedId}),
      write: true,
    );
  }

  Result<ServiceResponse, HttpError> _read(
    String path,
    Map<String, List<String>> query,
  ) {
    String? one(String name) => query[name]?.single;
    int? number(String name) => switch (one(name)) {
      final value? => int.parse(value),
      null => null,
    };
    // A list may be repeated or comma separated.
    Set<int>? numbers(String name) =>
        query[name]?.expand((value) => value.split(',')).map(int.parse).toSet();
    // Embedded objects are sent only when asked for.
    List<Map<String, Object?>> asked(Iterable<Map<String, Object?>> list) => [
      for (final record in list)
        {
          for (final MapEntry(:key, :value) in record.entries)
            if (!const {'artist', 'album'}.contains(key) ||
                one(key == 'artist' ? 'includeArtist' : 'includeAlbum') ==
                    'true')
              key: value,
        },
    ];
    bool has(List<Map<String, Object?>> list, int? id) =>
        list.any((item) => item['id'] == id);
    final missing = _json({'message': 'NotFound'}, 404);

    List<Map<String, Object?>> events(List<Map<String, Object?>> all) {
      final types = numbers('eventType');
      return [
        for (final event in all)
          if (types == null || types.contains(eventNumber(event['eventType'])))
            event,
      ];
    }

    switch (path) {
      case 'artist':
        return _json(artists);
      case 'album':
        final ids = numbers('albumIds');
        final artistId = number('artistId');
        final foreign = one('foreignAlbumId');
        return _json([
          for (final album in albums)
            if ((artistId == null || album['artistId'] == artistId) &&
                (ids == null || ids.contains(album['id'])) &&
                (foreign == null || album['foreignAlbumId'] == foreign))
              album,
        ]);
      case 'track':
        final ids = numbers('trackIds');
        final albumId = number('albumId');
        final artistId = number('artistId');
        return _json([
          for (final track in tracks)
            if ((albumId == null || track['albumId'] == albumId) &&
                (artistId == null || track['artistId'] == artistId) &&
                (ids == null || ids.contains(track['id'])))
              track,
        ]);
      case 'trackfile':
        final ids = numbers('trackFileIds');
        final albumId = number('albumId');
        final artistId = number('artistId');
        if (albumId != null && !has(albums, albumId)) return missing;
        if (artistId != null && !has(artists, artistId)) return missing;
        return _json([
          for (final file in trackFiles)
            if ((albumId == null || file['albumId'] == albumId) &&
                (artistId == null || file['artistId'] == artistId) &&
                (ids == null || ids.contains(file['id'])))
              file,
        ]);
      case 'artist/lookup':
        return _lookup(one('term')!, artistLookup, artistsById, 'Artist');
      case 'album/lookup':
        return _lookup(one('term')!, albumLookup, albumsById, 'Album');
      case 'queue':
        return _page(
          asked(
            queue.where(
              (item) =>
                  one('includeUnknownArtistItems') == 'true' ||
                  item['artistId'] != null,
            ),
          ),
          query,
        );
      case 'queue/details':
        final ids = numbers('albumIds');
        final artistId = number('artistId');
        return _json(
          asked(
            queue.where(
              (item) =>
                  (artistId == null || item['artistId'] == artistId) &&
                  (ids == null || ids.contains(item['albumId'])),
            ),
          ),
        );
      case 'history':
        final albumId = number('albumId');
        final matches = asked(
          events(history)
              .where((e) => albumId == null || e['albumId'] == albumId),
        );
        return _page(
          one('sortDirection') == 'ascending'
              ? matches.reversed.toList()
              : matches,
          query,
        );
      case 'history/since':
        final since = DateTime.parse(one('date')!);
        return _json(
          asked(
            events(historySince).where(
              (e) => !DateTime.parse(e['date']! as String).isBefore(since),
            ),
          ),
        );
      case 'history/artist':
        final artistId = number('artistId');
        final albumId = number('albumId');
        if (!has(artists, artistId)) return missing;
        return _json(
          asked(
            history.where(
              (e) =>
                  e['artistId'] == artistId &&
                  (albumId == null || e['albumId'] == albumId),
            ),
          ),
        );
      case 'blocklist':
        return _page(blocklist, query);
      case 'calendar':
        return _json(
          asked(
            calendar.where(
              (a) => one('unmonitored') == 'true' || a['monitored'] == true,
            ),
          ),
        );
      case 'wanted/missing':
        return _page(asked(wantedMissing), query);
      case 'wanted/cutoff':
        return _page(asked(wantedCutoff), query);
      case 'release':
        return _json(
          records(
            query.containsKey('albumId')
                ? 'manage_releases_album'
                : 'manage_releases',
          ),
        );
      case 'manualimport':
        return _json(manualImport);
      case 'qualitydefinition':
        return _json(records('qualitydefinition'));
      case 'qualityprofile':
        return _json(qualityProfiles);
      case 'metadataprofile':
        return _json(metadataProfiles);
      case 'rootfolder':
        return _json(rootFolders);
      case 'tag':
        return _json(tags);
      case 'health':
        return _json(health);
      case 'diskspace':
        return _json(diskSpace);
      case 'system/status':
        return _json(record('system_status'));
    }
    if (path == 'command/${command['id']}') return _json(command);
    if (RegExp(r'^(artist|album)/(\d+)$').firstMatch(path) case final match?) {
      final held = match[1] == 'artist' ? artists : albums;
      final found = held.where((item) => item['id'] == int.parse(match[2]!));
      return found.isEmpty ? missing : _json(found.single);
    }
    return missing;
  }

  Result<ServiceResponse, HttpError> _lookup(
    String term,
    List<Map<String, Object?>> searched,
    List<Map<String, Object?>> byForeignId,
    String kind,
  ) {
    if (term == searchTerm) return _json(searched);
    return _json(
      [
        // First what was recorded for an id: the searches are from before the
        // server had artist 1, and would not name it.
        for (final item in [...byForeignId, ...searched])
          if (term == 'lidarr:${item['foreign${kind}Id']}') item,
      ].take(1).toList(),
    );
  }

  Result<ServiceResponse, HttpError> _json(Object? json, [int status = 200]) =>
      _answer(status, jsonEncode(json));

  Result<ServiceResponse, HttpError> _page(
    List<Map<String, Object?>> all,
    Map<String, List<String>> query,
  ) {
    final page = int.parse(query['page']?.single ?? '1');
    final pageSize = int.parse(query['pageSize']?.single ?? '10');
    return _json({
      'page': page,
      'pageSize': pageSize,
      'totalRecords': all.length,
      'records': all.sublist(
        min((page - 1) * pageSize, all.length),
        min(page * pageSize, all.length),
      ),
    });
  }
}

/// The number Lidarr's `EntityHistoryEventType` gives the word of a record.
int eventNumber(Object? word) => const [
  'unknown',
  'grabbed',
  'artistFolderImported',
  'trackFileImported',
  'downloadFailed',
  'trackFileDeleted',
  'trackFileRenamed',
  'albumImportIncomplete',
  'downloadImported',
  'trackFileRetagged',
  'downloadIgnored',
].indexOf(word! as String);

/// Behaves as the core's cache of one instance does.
class FakeCache implements CacheScope {
  final _entries = <(MediaKind, int), CacheEntry>{};
  final _fetches = <(MediaKind, int?), DateTime>{};

  static const _children = {
    MediaKind.artist: MediaKind.album,
    MediaKind.album: MediaKind.track,
  };

  @override
  Future<CacheSnapshot?> read(MediaKind kind, {int? parentRemoteId}) async {
    final fetchedAt = _fetches[(kind, parentRemoteId)];
    if (fetchedAt == null) return null;
    final entries =
        [
          for (final entry in _entries.values)
            if (entry.kind == kind &&
                (parentRemoteId == null ||
                    entry.parentRemoteId == parentRemoteId))
              entry,
        ]..sort((a, b) {
          final byTitle = a.sortTitle.compareTo(b.sortTitle);
          return byTitle != 0 ? byTitle : a.remoteId.compareTo(b.remoteId);
        });
    return CacheSnapshot(entries: entries, fetchedAt: fetchedAt);
  }

  @override
  Future<CacheEntry?> entry(MediaKind kind, int remoteId) async =>
      _entries[(kind, remoteId)];

  @override
  Future<void> replace(
    MediaKind kind,
    List<CacheEntry> entries, {
    int? parentRemoteId,
  }) async {
    for (final entry in entries) {
      _check(entry);
      expect(entry.kind, kind);
      if (parentRemoteId != null) {
        expect(entry.parentRemoteId, parentRemoteId);
      }
    }
    final kept = {for (final entry in entries) entry.remoteId};
    final gone = [
      for (final entry in _entries.values)
        if (entry.kind == kind &&
            (parentRemoteId == null ||
                entry.parentRemoteId == parentRemoteId) &&
            !kept.contains(entry.remoteId))
          entry.remoteId,
    ];
    for (final id in gone) {
      _drop(kind, id);
    }
    for (final entry in entries) {
      _entries[(kind, entry.remoteId)] = entry;
    }
    final now = DateTime.now().toUtc();
    if (parentRemoteId == null) {
      _fetches.removeWhere((key, _) => key.$1 == kind);
    }
    _fetches[(kind, parentRemoteId)] = now;
  }

  @override
  Future<void> put(CacheEntry entry) async {
    _check(entry);
    _entries[(entry.kind, entry.remoteId)] = entry;
  }

  @override
  Future<void> remove(MediaKind kind, int remoteId) async {
    _drop(kind, remoteId);
    _removals.add(
      ItemRef(instanceId: instanceId, kind: kind, remoteId: remoteId),
    );
  }

  void _drop(MediaKind kind, int remoteId) {
    _entries.remove((kind, remoteId));
    final child = _children[kind];
    if (child == null) return;
    _fetches.remove((child, remoteId));
    final under = [
      for (final entry in _entries.values)
        if (entry.kind == child && entry.parentRemoteId == remoteId)
          entry.remoteId,
    ];
    for (final id in under) {
      _drop(child, id);
    }
  }

  final _removals = StreamController<ItemRef>.broadcast();

  @override
  Stream<ItemRef> get removals => _removals.stream;

  Cached<List<ServerOption>>? _options;

  @override
  Future<Cached<List<ServerOption>>?> readOptions() async => _options;

  @override
  Future<void> replaceOptions(List<ServerOption> options) async =>
      _options = Cached(options, fetchedAt: DateTime.now().toUtc());

  void _check(CacheEntry entry) => expect(entry.instanceId, instanceId);
}

class _FakeArtwork extends Fake implements ArtworkLoader {}

class _FakeNavigator extends Fake implements AppNavigator {}

class _FakeLogger implements Logger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// The Lidarr module's capabilities against [server], through the allow-list.
/// Create inside a test or `setUp`.
class Harness {
  Harness({FakeLidarr? server, ArtworkLoader? artwork, AppNavigator? navigator})
    : server = server ?? FakeLidarr() {
    context = InstanceContext(
      instance: Instance(
        id: instanceId,
        profileId: 'p1',
        name: 'Home',
        serviceType: 'lidarr',
        url: Uri.parse('http://server.test/lidarr'),
        authKind: AuthKind.apiKey,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      http: AllowListClient(allowList, this.server),
      artwork: artwork ?? _FakeArtwork(),
      navigator: navigator ?? _FakeNavigator(),
      cache: cache,
      logger: _FakeLogger(),
    );
  }

  final FakeLidarr server;
  final cache = FakeCache();

  /// What the module is given for the instance.
  late final InstanceContext context;

  LibraryProvider get library => _capability<LibraryProvider>();

  HistoryProvider get history => _capability<HistoryProvider>();

  LookupProvider get lookup => _capability<LookupProvider>();

  QueueProvider get queue => _capability<QueueProvider>();

  CalendarProvider get calendar => _capability<CalendarProvider>();

  WantedProvider get wanted => _capability<WantedProvider>();

  HealthProvider get health => _capability<HealthProvider>();

  CommandProvider get commands => _capability<CommandProvider>();

  ReleaseProvider get releases => _capability<ReleaseProvider>();

  /// The requests, each as its method and path.
  List<String> get asked => [
    for (final request in server.requests)
      '${request.method.name} ${request.path}',
  ];

  T _capability<T extends Capability>() {
    final found = LidarrModule().capability<T>(context);
    expect(found, isNotNull, reason: 'Lidarr provides $T');
    return found!;
  }
}

/// How a request appears in [Harness.asked].
String line(HttpMethod method, String path) => '${method.name} api/v1/$path';

/// The body of [request] as the server would receive it.
Object? sentBody(ServiceRequest request) =>
    jsonDecode(jsonEncode((request.body! as JsonBody).value));

/// The value of a result that must have succeeded.
Future<T> ok<T>(ServiceResult<T> result) async => switch (await result) {
  Ok(:final value) => value,
  Err(:final error) => fail('failed with ${error.runtimeType}'),
};

/// The failure of a result that must not have succeeded.
Future<ServiceFailure> failureOf<T>(ServiceResult<T> result) async =>
    switch (await result) {
      Ok() => fail('succeeded'),
      Err(:final error) => error,
    };

/// Asserts that [call] is a programming error. Nothing may have been sent,
/// which the caller checks.
Future<void> expectProgrammingError(Future<Object?> Function() call) =>
    expectLater(Future.sync(call), throwsArgumentError);

/// The failures a write can meet.
final writeFailures = <String, (Result<ServiceResponse, HttpError>, Type)>{
  'an unreachable server': (const Err(HttpError(Unreachable())), Unreachable),
  'a rejected key': (FakeLidarr.body('', status: 401), AuthFailed),
  'a refusal': (FakeLidarr.body('', status: 403), Forbidden),
  'a server error': (
    FakeLidarr.body('{"message":"Example"}', status: 500),
    ServerError,
  ),
  'an unknown outcome': (
    const Err(HttpError(OutcomeUnknown())),
    OutcomeUnknown,
  ),
};
