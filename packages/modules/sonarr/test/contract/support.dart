// A Sonarr and a cache to run the module's adapters against.
//
// The fixtures were recorded from Sonarr 4.0.20.3014 in the dev stack's image,
// with qBittorrent as its download client, and passed
// tool/sanitize_fixture.dart. The server had a URL base, which was cut from the
// cover addresses before that; the episode lists are cut down to a few seasons'
// first episodes, so they do not add up to the series' statistics. The queue
// was recorded before an episode file was imported and another deleted, so it
// still lists the imported one. What the tests need beyond the recordings they
// change here.
//
// The server answers as the recorded one did: embedded objects only when asked
// for, an empty list for the episodes of a series it does not have, 404 for
// that series' files and history, and 500 for an episode id it does not have.
//
// The lookups and the answers to adding were recorded from another throwaway
// server of the same image: a search that finds a series it has and some it does
// not, cut to four results, a lookup by TVDB id, an accepted add and two refused
// ones. An add is refused for a series it has, a root folder or quality profile
// it does not have and a monitoring value it does not know.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarr/sonarr_module.dart';

import '../allow_list.dart';

const instanceId = 'i1';

Object? _decode(String name) =>
    jsonDecode(File('test/fixtures/4.0.20.3014/$name.json').readAsStringSync());

/// A fresh copy of a recorded list.
List<Map<String, Object?>> records(String name) =>
    (_decode(name)! as List<Object?>).cast<Map<String, Object?>>();

/// A fresh copy of a recorded object.
Map<String, Object?> record(String name) =>
    _decode(name)! as Map<String, Object?>;

/// A fresh copy of the records of a recorded page.
List<Map<String, Object?>> pageRecords(String name) =>
    ((_decode(name)! as Map<String, Object?>)['records']! as List<Object?>)
        .cast<Map<String, Object?>>();

/// The one of [list] with [id].
Map<String, Object?> byId(List<Map<String, Object?>> list, int id) =>
    list.singleWhere((record) => record['id'] == id);

ItemRef seriesRef(int id) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.series, remoteId: id);

ItemRef episodeRef(int id) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.episode, remoteId: id);

/// What the recorded server takes as `addOptions.monitor`.
const _monitorTypes = {
  'unknown',
  'all',
  'future',
  'missing',
  'existing',
  'firstSeason',
  'lastSeason',
  'latestSeason',
  'pilot',
  'recent',
  'monitorSpecials',
  'unmonitorSpecials',
  'none',
  'skip',
};

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

/// Answers the reads of the library from [series], [episodes], [queue] and the
/// other lists, which a test may change, and takes the adding of a series. As
/// with the core's client, nothing is sent twice.
class FakeSonarr implements ServiceHttpClient {
  final series = records('series');
  final episodes = <int, List<Map<String, Object?>>>{
    1: records('episode_1'),
    4: records('episode_4'),
  };
  final episodeFiles = <int, List<Map<String, Object?>>>{
    1: records('episodefile_1'),
  };
  final queue = pageRecords('queue');

  /// The history of series 1, newest first.
  final history = records('history_series');
  final qualityProfiles = records('qualityprofile');
  final rootFolders = records('rootfolder');
  final tags = records('tag');

  /// What a search for [searchTerm] finds.
  final lookupResults = records('series_lookup');
  static const searchTerm = 'planet earth';

  /// What `tvdb:79257` finds.
  final tvdbLookup = records('series_lookup_tvdb');

  /// The id given to a series that is added.
  static const addedId = 42;

  /// If set, adding gets this, and the library does not change.
  Result<ServiceResponse, HttpError>? addAnswer;

  final requests = <ServiceRequest>[];

  /// If set, every request gets this.
  Result<ServiceResponse, HttpError>? always;

  /// Answers for single paths, below `api/v3/`.
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
    expect(request.path, startsWith('api/v3/'));
    final path = request.path.substring('api/v3/'.length);
    if (request.method != HttpMethod.get) {
      expect(
        (request.method, path),
        (HttpMethod.post, 'series'),
        reason: 'the only write tested',
      );
      expect(request.query, isEmpty);
      return always ?? addAnswer ?? _add(request.body);
    }
    return always ?? overrides[path] ?? _route(path, request.query);
  }

  Result<ServiceResponse, HttpError> _add(RequestBody? body) {
    expect(body, isA<JsonBody>());
    // As the server would receive it.
    final sent = jsonDecode(
      jsonEncode((body! as JsonBody).value),
    ) as Map<String, Object?>;
    Result<ServiceResponse, HttpError> refuse(Object? json) =>
        _answer(400, jsonEncode(json), write: true);

    if (sent['addOptions'] case {'monitor': final String monitor}
        when !_monitorTypes.contains(monitor)) {
      return refuse({
        'title': 'One or more validation errors occurred.',
        'status': 400,
        'errors': {
          r'$.addOptions.monitor': ['The JSON value could not be converted.'],
        },
      });
    }
    if (series.any((s) => s['tvdbId'] == sent['tvdbId'])) {
      return refuse(records('series_add_exists'));
    }
    if (!rootFolders.any((f) => f['path'] == sent['rootFolderPath'])) {
      return refuse(records('series_add_bad_root'));
    }
    if (!qualityProfiles.any((p) => p['id'] == sent['qualityProfileId'])) {
      return refuse([
        {
          'propertyName': 'QualityProfileId',
          'errorMessage': 'Quality Profile does not exist',
          'errorCode': 'QualityProfileExistsValidator',
        },
      ]);
    }
    final added = {
      ...record('series_add'),
      'tvdbId': sent['tvdbId'],
      'title': sent['title'],
      'id': addedId,
    };
    series.add(added);
    return _answer(201, jsonEncode(added), write: true);
  }

  Result<ServiceResponse, HttpError> _route(
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
    List<Map<String, Object?>> only(
      Iterable<Map<String, Object?>> list,
      Map<String, String> flags,
    ) => [
      for (final record in list)
        {
          for (final MapEntry(:key, :value) in record.entries)
            if (!flags.containsKey(key) || one(flags[key]!) == 'true')
              key: value,
        },
    ];

    const queueFlags = {'series': 'includeSeries', 'episode': 'includeEpisode'};
    const episodeFlags = {
      'series': 'includeSeries',
      'episodeFile': 'includeEpisodeFile',
      'images': 'includeImages',
    };
    final hasSeries = series.any((s) => s['id'] == number('seriesId'));
    final noSuchSeries = _json({'message': 'Series does not exist'}, 404);

    switch (path) {
      case 'series':
        return _json(series);
      case 'series/lookup':
        final term = one('term')!;
        if (term == 'tvdb:79257') return _json(tvdbLookup);
        if (RegExp(r'^tvdb:(\d+)$').firstMatch(term) case final match?) {
          final id = int.parse(match[1]!);
          return _json(lookupResults.where((r) => r['tvdbId'] == id).toList());
        }
        return _json(term == searchTerm ? lookupResults : const <Object>[]);
      case 'episode':
        final all = episodes.values.expand((list) => list);
        if (numbers('episodeIds') case final ids?) {
          final found = all.where((e) => ids.contains(e['id'])).toList();
          return found.length == ids.length
              ? _json(only(found, episodeFlags))
              : _json({
                  'message':
                      'Expected query to return ${ids.length} rows but '
                      'returned ${found.length}',
                }, 500);
        }
        final season = number('seasonNumber');
        return _json(
          only(
            (episodes[number('seriesId')] ?? const []).where(
              (e) => season == null || e['seasonNumber'] == season,
            ),
            episodeFlags,
          ),
        );
      case 'episodefile':
        if (numbers('episodeFileIds') case final ids?) {
          return _json([
            for (final file in episodeFiles.values.expand((list) => list))
              if (ids.contains(file['id'])) file,
          ]);
        }
        if (!hasSeries) return noSuchSeries;
        return _json(episodeFiles[number('seriesId')] ?? const <Object>[]);
      case 'queue':
        return _page(
          only(queue, queueFlags),
          page: number('page') ?? 1,
          pageSize: number('pageSize') ?? 10,
        );
      case 'queue/details':
        final ids = numbers('episodeIds');
        final seriesId = number('seriesId');
        return _json(
          only(
            queue.where(
              (item) =>
                  (seriesId == null || item['seriesId'] == seriesId) &&
                  (ids == null || ids.contains(item['episodeId'])),
            ),
            queueFlags,
          ),
        );
      case 'history':
        final episodeId = number('episodeId');
        final matches = only(
          history.where(
            (e) => episodeId == null || e['episodeId'] == episodeId,
          ),
          queueFlags,
        );
        return _page(
          one('sortDirection') == 'ascending'
              ? matches.reversed.toList()
              : matches,
          page: number('page') ?? 1,
          pageSize: number('pageSize') ?? 10,
        );
      case 'history/series':
        if (!hasSeries) return noSuchSeries;
        final season = number('seasonNumber');
        // The records name an episode, whose season is looked up.
        final ofSeason = {
          for (final e
              in episodes[number('seriesId')] ?? <Map<String, Object?>>[])
            if (e['seasonNumber'] == season) e['id'],
        };
        return _json(
          only(
            history.where(
              (e) =>
                  e['seriesId'] == number('seriesId') &&
                  (season == null || ofSeason.contains(e['episodeId'])),
            ),
            queueFlags,
          ),
        );
      case 'qualityprofile':
        return _json(qualityProfiles);
      case 'rootfolder':
        return _json(rootFolders);
      case 'tag':
        return _json(tags);
    }
    if (RegExp(r'^series/(\d+)$').firstMatch(path) case final match?) {
      final id = int.parse(match[1]!);
      final found = series.where((s) => s['id'] == id);
      return found.isEmpty
          ? _json({'title': 'Not Found', 'status': 404}, 404)
          : _json(found.single);
    }
    return _json({'message': 'NotFound'}, 404);
  }

  Result<ServiceResponse, HttpError> _json(Object? json, [int status = 200]) =>
      _answer(status, jsonEncode(json));

  Result<ServiceResponse, HttpError> _page(
    List<Map<String, Object?>> all, {
    required int page,
    required int pageSize,
  }) => _json({
    'page': page,
    'pageSize': pageSize,
    'totalRecords': all.length,
    'records': all.sublist(
      min((page - 1) * pageSize, all.length),
      min(page * pageSize, all.length),
    ),
  });
}

/// Behaves as the core's cache of one instance does.
class FakeCache implements CacheScope {
  final _entries = <(MediaKind, int), CacheEntry>{};
  final _fetches = <(MediaKind, int?), DateTime>{};

  static const _children = {MediaKind.series: MediaKind.episode};

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
    _entries.removeWhere(
      (key, entry) => key.$1 == child && entry.parentRemoteId == remoteId,
    );
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

/// The Sonarr module's capabilities against [server], through the allow-list.
/// Create inside a test or `setUp`.
class Harness {
  Harness({
    FakeSonarr? server,
    FakeCache? cache,
    ArtworkLoader? artwork,
    AppNavigator? navigator,
  }) : server = server ?? FakeSonarr(),
       cache = cache ?? FakeCache() {
    context = InstanceContext(
      instance: Instance(
        id: instanceId,
        profileId: 'p1',
        name: 'Home',
        serviceType: 'sonarr',
        url: Uri.parse('http://server.test/sonarr'),
        authKind: AuthKind.apiKey,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      http: AllowListClient(allowList, this.server),
      artwork: artwork ?? _FakeArtwork(),
      navigator: navigator ?? _FakeNavigator(),
      cache: this.cache,
      logger: _FakeLogger(),
    );
  }

  final FakeSonarr server;
  final FakeCache cache;

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

  T _capability<T extends Capability>() {
    final found = SonarrModule().capability<T>(context);
    expect(found, isNotNull, reason: 'Sonarr provides $T');
    return found!;
  }
}

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
