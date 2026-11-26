import 'dart:convert';

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../models/json_fields.dart';

const _apiPath = 'api/v3';

// How Sonarr says, with status 500, that it does not have the one record named:
// to `episode?episodeIds=`, and to a delete or a season pass of a series.
const _noSuchRecord = 'Expected query to return 1 rows but returned 0';

/// Sonarr's requests for one instance.
///
/// As in [ServarrClient], a failure of the HTTP client is returned unchanged,
/// nothing is retried, and an answer of another shape is [MalformedResponse].
final class SonarrApi {
  /// The API of the instance of [context].
  SonarrApi(InstanceContext context)
    : instanceId = context.instance.id,
      _http = context.http,
      _shared = ServarrClient(
        context.http,
        apiPath: _apiPath,
        includeUnknownParameter: 'includeUnknownSeriesItems',
        refs: (record) => _refs(context.instance.id, record),
      );

  /// The instance whose items the records are.
  final String instanceId;

  /// The client for what the family shares as it is.
  ServarrClient get shared => _shared;

  final ServiceHttpClient _http;
  final ServarrClient _shared;

  /// The key of the series [id].
  ItemRef seriesRef(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.series, remoteId: id);

  /// The key of the episode [id].
  ItemRef episodeRef(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.episode, remoteId: id);

  /// Every series, as received.
  ServiceResult<List<JsonObject>> allSeries() => _get('series', asObjects);

  /// One series, as received.
  ServiceResult<JsonObject> series(int id) => _get('series/$id', asObject);

  /// The series the server's metadata source finds for [term], which may be
  /// `tvdb:<id>`. One the server has carries its id.
  ServiceResult<List<JsonObject>> lookup(String term) => _get(
    'series/lookup',
    asObjects,
    query: {
      'term': [term],
    },
  );

  /// The root folders, as received.
  ServiceResult<List<JsonObject>> rootFolders() =>
      _get('rootfolder', asObjects);

  /// Adds [series], sending it once, and gives its id. If the server accepts it
  /// without saying which series it made, that is [OutcomeUnknown].
  ServiceResult<int> addSeries(JsonObject series) async {
    final request = ServiceRequest(
      HttpMethod.post,
      '$_apiPath/series',
      body: JsonBody(series),
    );
    switch (await _http.send(request)) {
      case Err(:final error):
        return Err(_saysItExists(error) ? const Conflict() : error.failure);
      case Ok(:final value):
        final Object? added;
        try {
          added = jsonDecode(value.text);
        } on FormatException {
          return const Err(OutcomeUnknown());
        }
        return switch (added) {
          {'id': final int id} when id > 0 => Ok(id),
          _ => const Err(OutcomeUnknown()),
        };
    }
  }

  /// The episodes of a series, with files and images. A series the server does
  /// not have gets an empty list.
  ServiceResult<List<JsonObject>> episodes(int seriesId) => _get(
    'episode',
    asObjects,
    query: {
      ..._ofSeries(seriesId),
      'includeEpisodeFile': ['true'],
      'includeImages': ['true'],
    },
  );

  /// One episode, with its series, file and images. One the server does not
  /// have is [NotFound].
  ServiceResult<JsonObject> episode(int id) => _get(
    'episode',
    (json) => switch (asObjects(json)) {
      [final record] => record,
      _ => throw const FormatException('Not one episode'),
    },
    query: {
      'episodeIds': ['$id'],
      'includeSeries': ['true'],
      'includeEpisodeFile': ['true'],
      'includeImages': ['true'],
    },
    classify: (error) =>
        _saysNoSuchRecord(error) ? const NotFound() : error.failure,
  );

  /// The episode files of a series, as received.
  ServiceResult<List<JsonObject>> episodeFiles(int seriesId) =>
      _get('episodefile', asObjects, query: _ofSeries(seriesId));

  /// The whole download queue.
  ServiceResult<List<QueueItem>> queue() => _shared.queue();

  /// The events of a series, or of one of its seasons, newest first.
  ServiceResult<List<HistoryEvent>> seriesHistory(
    int seriesId, {
    int? seasonNumber,
  }) => _shared.itemHistory(
    'history/series',
    query: {
      ..._ofSeries(seriesId),
      if (seasonNumber != null) 'seasonNumber': ['$seasonNumber'],
    },
  );

  /// One page of the events of an episode, newest first.
  ServiceResult<ResultPage<HistoryEvent>> episodeHistory(
    int episodeId, {
    required int page,
  }) => _shared.history(
    page: page,
    filter: {
      'episodeId': ['$episodeId'],
    },
  );

  /// Quality profiles, root folders and tags.
  ServiceResult<List<ServerOption>> options() => _shared.options();

  /// Reads the series [id], lets [change] alter it and writes all of it back.
  ServiceResult<void> updateSeries(
    int id,
    void Function(JsonObject series) change,
  ) => _shared.update('series/$id', change);

  /// [updateSeries] with the fields set in [changes].
  ServiceResult<void> editSeries(int id, ItemEdit changes) =>
      _shared.edit('series/$id', changes);

  /// Changes the series [ids] at once.
  ServiceResult<void> editAllSeries(List<int> ids, BulkEdit changes) =>
      _shared.bulkEdit(
        'series/editor',
        idsField: 'seriesIds',
        ids: ids,
        changes: changes,
      );

  /// Turns monitoring of the episodes [ids] on or off.
  ServiceResult<void> monitorEpisodes(
    List<int> ids, {
    required bool monitored,
  }) => _write(
    HttpMethod.put,
    'episode/monitor',
    body: JsonBody({'episodeIds': ids, 'monitored': monitored}),
  );

  /// Has the series [id] monitored as [monitor] says. A series the server does
  /// not have is [NotFound].
  ServiceResult<void> seasonPass(int id, {required String monitor}) => _write(
    HttpMethod.post,
    'seasonpass',
    body: JsonBody({
      'series': [
        {'id': id},
      ],
      'monitoringOptions': {'monitor': monitor},
    }),
    classify: (error) => switch (error.failure) {
      _ when _saysNoSuchRecord(error) => const NotFound(),
      // The path names no series, so this does not say that it is gone.
      NotFound() => const ServerError(statusCode: 404),
      final failure => failure,
    },
  );

  /// Deletes the series [id]. One the server does not have is [NotFound].
  ///
  /// Both flags are always sent: what is deleted never rests on a default.
  ServiceResult<void> deleteSeries(
    int id, {
    required bool deleteFiles,
    required bool addImportListExclusion,
  }) => _write(
    HttpMethod.delete,
    'series/$id',
    query: {
      'deleteFiles': ['$deleteFiles'],
      'addImportListExclusion': ['$addImportListExclusion'],
    },
    classify: (error) =>
        _saysNoSuchRecord(error) ? const NotFound() : error.failure,
  );

  /// Deletes the episode file [id].
  ServiceResult<void> deleteEpisodeFile(int id) =>
      _write(HttpMethod.delete, 'episodefile/$id');

  static Map<String, List<String>> _ofSeries(int id) => {
    'seriesId': ['$id'],
  };

  /// One write, sent once. What a successful one answers is not read.
  ServiceResult<void> _write(
    HttpMethod method,
    String path, {
    Map<String, List<String>> query = const {},
    RequestBody? body,
    ServiceFailure Function(HttpError error)? classify,
  }) async {
    final request = ServiceRequest(
      method,
      '$_apiPath/$path',
      query: query,
      body: body,
    );
    return switch (await _http.send(request)) {
      Ok() => const Ok(null),
      Err(:final error) => Err(classify?.call(error) ?? error.failure),
    };
  }

  ServiceResult<T> _get<T>(
    String path,
    T Function(Object? json) decode, {
    Map<String, List<String>> query = const {},
    ServiceFailure Function(HttpError error)? classify,
  }) async {
    final request = ServiceRequest(
      HttpMethod.get,
      '$_apiPath/$path',
      query: query,
    );
    switch (await _http.send(request)) {
      case Err(:final error):
        return Err(classify?.call(error) ?? error.failure);
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

bool _saysNoSuchRecord(HttpError error) {
  final response = error.response;
  return response != null &&
      response.statusCode == 500 &&
      response.text.contains(_noSuchRecord);
}

/// Whether a refused add names the validator for a series the server has. Its
/// other refusals, a folder already in use included, stay as they are.
bool _saysItExists(HttpError error) {
  final response = error.response;
  if (error.failure is! Validation || response == null) return false;
  final Object? refusals;
  try {
    refusals = jsonDecode(response.text);
  } on FormatException {
    return false;
  }
  return refusals is List<Object?> &&
      refusals.any(
        (refusal) => switch (refusal) {
          {'errorCode': 'SeriesExistsValidator'} => true,
          _ => false,
        },
      );
}

/// A queue or history record is about an episode of a series.
ServarrRefs _refs(String instanceId, JsonObject record) {
  ItemRef? ref(MediaKind kind, String field) => switch (record[field]) {
    final int id when id > 0 => ItemRef(
      instanceId: instanceId,
      kind: kind,
      remoteId: id,
    ),
    _ => null,
  };
  return (
    item: ref(MediaKind.episode, 'episodeId'),
    parent: ref(MediaKind.series, 'seriesId'),
  );
}
