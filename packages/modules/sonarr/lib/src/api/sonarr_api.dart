import 'dart:convert';

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../models/json_fields.dart';

const _apiPath = 'api/v3';

// How `episode?episodeIds=` says that it has no such episode: with status 500.
const _noSuchEpisode = 'Expected query to return 1 rows but returned 0';

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
    classify: (error) => switch (error.response) {
      final response?
          when response.statusCode == 500 &&
              response.text.contains(_noSuchEpisode) =>
        const NotFound(),
      _ => error.failure,
    },
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

  static Map<String, List<String>> _ofSeries(int id) => {
    'seriesId': ['$id'],
  };

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
