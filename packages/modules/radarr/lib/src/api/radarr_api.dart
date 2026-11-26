import 'dart:convert';

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

const _apiPath = 'api/v3';

/// Radarr's reads, its add and its deletes, for one instance.
///
/// As in [ServarrClient], a failure of the HTTP client is returned unchanged,
/// nothing is retried, and an answer to a read of another shape is
/// [MalformedResponse].
final class RadarrApi {
  /// The API of the instance of [context].
  RadarrApi(InstanceContext context)
    : _http = context.http,
      shared = ServarrClient(
        context.http,
        apiPath: _apiPath,
        includeUnknownParameter: 'includeUnknownMovieItems',
        refs: (record) => (
          item: switch (record['movieId']) {
            final int id when id > 0 => ItemRef(
              instanceId: context.instance.id,
              kind: MediaKind.movie,
              remoteId: id,
            ),
            _ => null,
          },
          parent: null,
        ),
      );

  final ServiceHttpClient _http;

  /// The reads the Servarr family has in common, set up for Radarr.
  final ServarrClient shared;

  /// Every movie, as received.
  ServiceResult<List<JsonObject>> movies() => _get('movie', _objects);

  /// One movie, as received.
  ServiceResult<JsonObject> movie(int id) => _get('movie/$id', _object);

  /// The files of one movie, as received.
  ServiceResult<List<JsonObject>> movieFiles(int movieId) =>
      _get('moviefile', _objects, query: _ofMovie(movieId));

  /// The cast and crew of one movie, as received.
  ServiceResult<List<JsonObject>> credits(int movieId) =>
      _get('credit', _objects, query: _ofMovie(movieId));

  /// The movies the server finds for [term], as received.
  ServiceResult<List<JsonObject>> lookup(String term) => _get(
    'movie/lookup',
    _objects,
    query: {
      'term': [term],
    },
  );

  /// The root folders, as received.
  ServiceResult<List<JsonObject>> rootFolders() => _get('rootfolder', _objects);

  /// Adds [movie], once. What the answer means is for the caller to say.
  Future<Result<ServiceResponse, HttpError>> addMovie(JsonObject movie) =>
      _http.send(
        ServiceRequest(
          HttpMethod.post,
          '$_apiPath/movie',
          body: JsonBody(movie),
        ),
      );

  /// Deletes the movie [id], once. Both choices are stated, so that neither is
  /// left to the server.
  ServiceResult<void> deleteMovie(
    int id, {
    required bool deleteFiles,
    required bool addImportExclusion,
  }) => _delete(
    'movie/$id',
    query: {
      'deleteFiles': ['$deleteFiles'],
      'addImportExclusion': ['$addImportExclusion'],
    },
  );

  /// Deletes the movie file [id], once.
  ServiceResult<void> deleteMovieFile(int id) => _delete('moviefile/$id');

  /// The whole download queue.
  ServiceResult<List<QueueItem>> queue() => shared.queue();

  /// The events of one movie, newest first.
  ServiceResult<List<HistoryEvent>> movieHistory(int movieId) =>
      shared.itemHistory('history/movie', query: _ofMovie(movieId));

  /// Quality profiles, root folders and tags.
  ServiceResult<List<ServerOption>> options() => shared.options();

  static Map<String, List<String>> _ofMovie(int id) => {
    'movieId': ['$id'],
  };

  static JsonObject _object(Object? json) =>
      json is JsonObject ? json : throw const FormatException('Not an object');

  static List<JsonObject> _objects(Object? json) => json is List<Object?>
      ? [for (final entry in json) _object(entry)]
      : throw const FormatException('Not a list');

  // The server answers with nothing, so the answer is not read.
  ServiceResult<void> _delete(
    String path, {
    Map<String, List<String>> query = const {},
  }) async {
    final request = ServiceRequest(
      HttpMethod.delete,
      '$_apiPath/$path',
      query: query,
    );
    return switch (await _http.send(request)) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error.failure),
    };
  }

  ServiceResult<T> _get<T>(
    String path,
    T Function(Object? json) decode, {
    Map<String, List<String>> query = const {},
  }) async {
    final request = ServiceRequest(
      HttpMethod.get,
      '$_apiPath/$path',
      query: query,
    );
    switch (await _http.send(request)) {
      case Err(:final error):
        return Err(error.failure);
      case Ok(:final value):
        try {
          return Ok(decode(jsonDecode(value.text)));
        } on FormatException {
          // The exception quotes the body, so it goes no further.
          return const Err(MalformedResponse());
        }
    }
  }
}
