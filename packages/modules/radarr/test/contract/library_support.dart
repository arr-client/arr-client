// A Radarr that answers from recorded responses, and what the library tests
// need to talk to it through the module.
//
// test/fixtures/7.0.3.10918/ was recorded from a throwaway Radarr
// 7.0.3.10918 and went through tool/sanitize_fixture.dart, so titles, names,
// paths and remote addresses are placeholders. The qualityprofile and credit
// recordings were cut down to a few entries first. Tests compare with what the
// fixture says, and set in code the values that sanitizing took the shape from.
//
//   id  monitored  file  available  queued
//    1  yes        yes   yes        no
//    2  no         yes   yes        yes
//    3  yes        no    yes        yes
//    4  no         no    yes        no
//    5  yes        no    no         no
//    6  yes        no    yes        yes
//    7  yes        no    yes        no
//
// The queue also has one download that matches no movie.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import '../allow_list.dart';

const instanceId = 'i1';

/// A fresh copy of a recording, free to be changed by the test.
Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/7.0.3.10918/$name.json').readAsStringSync());

List<Map<String, Object?>> records(Object? list) =>
    (list! as List<Object?>).cast<Map<String, Object?>>().toList();

/// The record with [id] in the recording [name].
Map<String, Object?> recorded(String name, int id) =>
    records(fixture(name)).singleWhere((record) => record['id'] == id);

ItemRef movieRef(int id) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.movie, remoteId: id);

ServiceResponse _response(int status, String body, String? type) =>
    ServiceResponse(
      statusCode: status,
      bytes: utf8.encode(body),
      headers: {
        if (type != null) 'content-type': [type],
      },
    );

Result<ServiceResponse, HttpError> jsonAnswer(Object? value) =>
    Ok(_response(200, jsonEncode(value), 'application/json; charset=utf-8'));

/// A success whose body is [body] as it stands.
Result<ServiceResponse, HttpError> textAnswer(String body) =>
    Ok(_response(200, body, 'application/json; charset=utf-8'));

/// What the core client returns for a request that did not succeed.
Result<ServiceResponse, HttpError> failedAnswer(
  ServiceFailure failure, {
  int? status,
}) => Err(
  HttpError(
    failure,
    response: status == null ? null : _response(status, '', null),
  ),
);

/// Radarr's reads, as far as the library needs them. A success is [Ok] and
/// anything else a classified [Err], as `ServiceHttpClient` says.
class FakeRadarr implements ServiceHttpClient {
  /// The movies of `GET movie` and `GET movie/{id}`.
  List<Map<String, Object?>> movies = records(fixture('movie'));

  /// The queue; empty unless a test fills it with [recordedQueue].
  List<Map<String, Object?>> queue = [];

  /// Answers every request instead, as when the server cannot be reached.
  Result<ServiceResponse, HttpError>? down;

  /// Answers by path that replace the recorded ones.
  final answers = <String, Result<ServiceResponse, HttpError>>{};

  /// What was asked.
  final requests = <ServiceRequest>[];

  static List<Map<String, Object?>> recordedQueue() =>
      records((fixture('queue')! as Map<String, Object?>)['records']);

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    requests.add(request);
    return down ??
        answers[request.path] ??
        _answer(request) ??
        failedAnswer(const NotFound(), status: 404);
  }

  Result<ServiceResponse, HttpError>? _answer(ServiceRequest request) {
    final query = request.query;
    Set<int>? ids(String name) =>
        query[name]?.expand((value) => value.split(',')).map(int.parse).toSet();
    final movieId = ids('movieId');

    final path = request.path.replaceFirst('api/v3/', '');
    if (path.startsWith('movie/')) {
      final id = int.tryParse(path.substring('movie/'.length));
      // The single movie was recorded on its own; the others are as listed.
      final single = fixture('movie_1')! as Map<String, Object?>;
      for (final movie in movies) {
        if (movie['id'] == id) return jsonAnswer(id == 1 ? single : movie);
      }
      return null;
    }
    switch (path) {
      case 'movie':
        return jsonAnswer(movies);
      case 'moviefile':
        return jsonAnswer([
          for (final file in records(fixture('moviefile')))
            if (movieId?.contains(file['movieId']) ?? false) file,
        ]);
      case 'credit':
        return jsonAnswer(
          movieId!.contains(3) ? fixture('credit') : <Object>[],
        );
      case 'qualityprofile' || 'rootfolder' || 'tag':
        return jsonAnswer(fixture(path));
      case 'history/movie':
        final id = movieId!.single;
        return jsonAnswer(
          id == 1 || id == 4 ? fixture('history_movie_$id') : <Object>[],
        );
      case 'queue':
        final wanted = ids('movieIds');
        final matching = [
          for (final entry in queue)
            if (wanted == null || wanted.contains(entry['movieId'])) entry,
        ];
        final page = int.parse(query['page']?.single ?? '1');
        // Radarr's own page size when none is asked for.
        final size = int.parse(query['pageSize']?.single ?? '10');
        return jsonAnswer({
          'page': page,
          'pageSize': size,
          'totalRecords': matching.length,
          'records': matching.sublist(
            min((page - 1) * size, matching.length),
            min(page * size, matching.length),
          ),
        });
    }
    return null;
  }
}

/// The instance's cache, in memory.
class FakeCache implements CacheScope {
  /// When [replace] says the lists were fetched.
  static final listFetchedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);

  final entries = <(MediaKind, int), CacheEntry>{};
  final _fetched = <(MediaKind, int?)>{};

  @override
  Future<CacheSnapshot?> read(MediaKind kind, {int? parentRemoteId}) async {
    if (!_fetched.contains((kind, parentRemoteId))) return null;
    final found = [
      for (final entry in entries.values)
        if (entry.kind == kind &&
            (parentRemoteId == null || entry.parentRemoteId == parentRemoteId))
          entry,
    ]..sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
    return CacheSnapshot(entries: found, fetchedAt: listFetchedAt);
  }

  @override
  Future<CacheEntry?> entry(MediaKind kind, int remoteId) async =>
      entries[(kind, remoteId)];

  @override
  Future<void> replace(
    MediaKind kind,
    List<CacheEntry> entries, {
    int? parentRemoteId,
  }) async {
    this.entries.removeWhere(
      (_, entry) =>
          entry.kind == kind &&
          (parentRemoteId == null || entry.parentRemoteId == parentRemoteId),
    );
    for (final entry in entries) {
      expect(entry.kind, kind);
      await put(entry);
    }
    _fetched.add((kind, parentRemoteId));
  }

  @override
  Future<void> put(CacheEntry entry) async {
    expect(entry.instanceId, instanceId);
    entries[(entry.kind, entry.remoteId)] = entry;
  }

  @override
  Future<void> remove(MediaKind kind, int remoteId) async {
    entries.remove((kind, remoteId));
  }
}

class _FakeArtwork extends Fake implements ArtworkLoader {}

class _FakeNavigator extends Fake implements AppNavigator {}

class _SilentLogger implements Logger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// The module's capabilities for one instance of [server], behind the Radarr
/// allow-list. Create it inside the test.
class Harness {
  Harness() {
    context = InstanceContext(
      instance: Instance(
        id: instanceId,
        profileId: 'p1',
        name: 'Home',
        serviceType: 'radarr',
        url: Uri.parse('http://server.test/radarr'),
        authKind: AuthKind.apiKey,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      http: AllowListClient(allowList, server),
      artwork: _FakeArtwork(),
      navigator: _FakeNavigator(),
      cache: cache,
      logger: _SilentLogger(),
    );
  }

  final server = FakeRadarr();
  final cache = FakeCache();
  late final InstanceContext context;

  LibraryProvider get library =>
      RadarrModule().capability<LibraryProvider>(context) ??
      (throw TestFailure('Radarr has no LibraryProvider'));

  HistoryProvider get history =>
      RadarrModule().capability<HistoryProvider>(context) ??
      (throw TestFailure('Radarr has no HistoryProvider'));
}

/// The value of an operation that must succeed.
Future<T> succeed<T>(ServiceResult<T> operation) async =>
    switch (await operation) {
      Ok(:final value) => value,
      Err(:final error) => fail('Expected success, got $error'),
    };

/// The failure of an operation that must fail.
Future<ServiceFailure> failureOf<T>(ServiceResult<T> operation) async =>
    switch (await operation) {
      Ok(:final value) => fail('Expected a failure, got $value'),
      Err(:final error) => error,
    };

/// The movies by id.
Map<int, Movie> byId(List<LibraryItem> items) => {
  for (final item in items) item.ref.remoteId: item as Movie,
};
