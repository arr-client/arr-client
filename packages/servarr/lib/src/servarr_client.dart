import 'dart:convert';

import 'package:core/core.dart';

import 'json_reading.dart';
import 'records/command_record.dart';
import 'records/health_record.dart';
import 'records/history_record.dart';
import 'records/option_record.dart';
import 'records/queue_record.dart';
import 'servarr_refs.dart';
import 'servarr_status.dart';

/// The reads the services of the Servarr family have in common.
///
/// A failure of the HTTP client is returned unchanged and nothing is retried
/// here. An answer that cannot be understood is [MalformedResponse].
final class ServarrClient {
  /// A client of the API under [apiPath], such as `api/v3`.
  ///
  /// [includeUnknownParameter] is the service's queue flag for downloads it
  /// cannot match. [refs] reads the ids of each queue and history record.
  ServarrClient(
    this._http, {
    required this._apiPath,
    required this._includeUnknownParameter,
    required this._refs,
  });

  static const _queuePageSize = 250;
  static const _historyPageSize = 50;

  final ServiceHttpClient _http;
  final String _apiPath;
  final String _includeUnknownParameter;
  final ServarrRefs Function(JsonObject record) _refs;

  /// The application's name and version.
  ServiceResult<ServarrStatus> status() => _get('system/status', (json) {
    final status = asObject(json);
    return (
      appName: requireString(status, 'appName'),
      version: requireString(status, 'version'),
    );
  });

  /// Quality profiles, root folders and tags. Fails if any of them does.
  ServiceResult<List<ServerOption>> options() async {
    final options = <ServerOption>[];
    for (final (path, read) in const [
      ('qualityprofile', qualityProfileOption),
      ('rootfolder', rootFolderOption),
      ('tag', tagOption),
    ]) {
      switch (await _get(path, (json) => asObjects(json).map(read).toList())) {
        case Ok(:final value):
          options.addAll(value);
        case Err(:final error):
          return Err(error);
      }
    }
    return Ok(options);
  }

  /// The whole download queue, in the server's order, each entry once.
  /// Downloads the server cannot match are included.
  ServiceResult<List<QueueItem>> queue() async {
    // By id: the queue can change between pages, and past its end the server
    // answers with an earlier page again.
    final items = <int, QueueItem>{};
    for (var number = 1; ; number++) {
      final result = await _get(
        'queue',
        (json) => readPage(json, (record) => queueItem(record, _refs(record))),
        query: {
          'page': ['$number'],
          'pageSize': ['$_queuePageSize'],
          _includeUnknownParameter: ['true'],
        },
      );
      switch (result) {
        case Err(:final error):
          return Err(error);
        case Ok(:final value):
          final before = items.length;
          for (final item in value.records) {
            items.putIfAbsent(item.id, () => item);
          }
          // A page with nothing new ends the reading whatever the totals say,
          // so that a server repeating a page cannot keep it going.
          if (items.length == before ||
              number * value.pageSize >= value.totalRecords) {
            return Ok(items.values.toList());
          }
      }
    }
  }

  /// One page of the history, newest first. Pages start at 1. [filter] narrows
  /// it by the service's own parameters, such as `episodeId`.
  ServiceResult<ResultPage<HistoryEvent>> history({
    int page = 1,
    Map<String, List<String>> filter = const {},
  }) => _get(
    'history',
    (json) {
      final read = readPage(
        json,
        (record) => historyEvent(record, _refs(record)),
      );
      return ResultPage(
        items: read.records,
        page: page,
        hasMore: page * read.pageSize < read.totalRecords,
      );
    },
    query: {
      ...filter,
      'page': ['$page'],
      'pageSize': ['$_historyPageSize'],
      'sortKey': ['date'],
      'sortDirection': ['descending'],
    },
  );

  /// Where the command [commandId] is.
  ServiceResult<Command> commandStatus(int commandId) =>
      _get('command/$commandId', (json) => readCommand(asObject(json)));

  /// The events of one item, newest first, from the service's own read at
  /// [path], such as `history/movie`. The server does not page them.
  ServiceResult<List<HistoryEvent>> itemHistory(
    String path, {
    required Map<String, List<String>> query,
  }) => _get(path, (json) {
    final events = [
      for (final record in asObjects(json)) historyEvent(record, _refs(record)),
    ];
    // The id orders events of the same moment.
    return events..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  }, query: query);

  /// The problems the server reports.
  ServiceResult<List<HealthIssue>> health() =>
      _get('health', (json) => asObjects(json).map(healthIssue).toList());

  /// [decode] throws [FormatException] for a body it cannot understand.
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
