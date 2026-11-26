part of '../servarr_client.dart';

const _blocklistPageSize = 50;

/// The actions on the queue, the history and the blocklist, and manual import.
///
/// A write is sent once. What a successful one answers is not read, but for
/// [reprocess] and [importFiles].
///
/// A mixin, so that these are members of [ServarrClient]: callers need no
/// further import to see them.
mixin _ServarrActivity {
  /// The client these are members of.
  ServarrClient get _client;

  /// Removes the queue entry [queueId].
  ServiceResult<void> remove(int queueId, RemoveOptions options) =>
      _write(HttpMethod.delete, 'queue/$queueId', query: _removal(options));

  /// Removes the queue entries [queueIds] at once.
  ServiceResult<void> removeMany(
    List<int> queueIds,
    RemoveOptions options,
  ) async {
    if (queueIds.isEmpty) return const Ok(null);
    return _write(
      HttpMethod.delete,
      'queue/bulk',
      query: _removal(options),
      body: JsonBody({'ids': queueIds}),
    );
  }

  /// Grabs the delayed queue entry [queueId] at once.
  ServiceResult<void> grabNow(int queueId) =>
      _write(HttpMethod.post, 'queue/grab/$queueId');

  /// Marks the grab of the history event [eventId] as failed.
  ServiceResult<void> markFailed(int eventId) =>
      _write(HttpMethod.post, 'history/failed/$eventId');

  /// The events the server has after [since], newest first.
  ///
  /// The server compares fractions of a second but reports whole ones, so
  /// asking since a reported time leaves out that whole second.
  ServiceResult<List<HistoryEvent>> eventsSince(DateTime since) =>
      _client.itemHistory(
        'history/since',
        query: {
          'date': [since.toUtc().toIso8601String()],
        },
      );

  /// One page of the blocked releases, newest first. Pages start at 1.
  ServiceResult<ResultPage<BlocklistEntry>> blocklist({int page = 1}) =>
      _client.read(
        'blocklist',
        (json) {
          final read = readPage(
            json,
            (record) => blocklistEntry(record, _client.refs(record)),
          );
          return ResultPage(
            items: read.records,
            page: page,
            hasMore: page * read.pageSize < read.totalRecords,
          );
        },
        query: {
          'page': ['$page'],
          'pageSize': ['$_blocklistPageSize'],
          'sortKey': ['date'],
          'sortDirection': ['descending'],
        },
      );

  /// Removes [entryIds] from the blocklist.
  ServiceResult<void> unblock(List<int> entryIds) async => switch (entryIds) {
    [] => const Ok(null),
    [final id] => await _write(HttpMethod.delete, 'blocklist/$id'),
    _ => await _write(
      HttpMethod.delete,
      'blocklist/bulk',
      body: JsonBody({'ids': entryIds}),
    ),
  };

  /// The files of [item]'s download that await import. An entry without a
  /// download has none.
  ServiceResult<List<ManualImportCandidate>> importCandidates(
    QueueItem item, {
    required ServarrImportMapping mapping,
  }) async {
    final downloadId = item.downloadId;
    // Without a download the server would list a folder instead.
    if (downloadId == null || downloadId.isEmpty) return const Ok([]);
    return _client.read(
      'manualimport',
      (json) => [
        for (final record in asObjects(json)) importCandidate(record, mapping),
      ],
      query: {
        'downloadId': [downloadId],
        'filterExistingFiles': ['true'],
      },
    );
  }

  /// The qualities and languages a candidate can be corrected to. Fails if
  /// either cannot be read.
  ServiceResult<ImportChoices> importChoices() async {
    switch (await _client.read(
      'qualitydefinition',
      (json) => asObjects(json).map(definedQuality).toList(),
    )) {
      case Err(:final error):
        return Err(error);
      case Ok(value: final qualities):
        return _client.read(
          'language',
          (json) => ImportChoices(
            qualities: qualities,
            languages: [
              // Below 0 are 'Any' and 'Original', which no file is in.
              for (final language in asObjects(json).map(readLanguage))
                if (language.id >= 0) language,
            ],
          ),
        );
    }
  }

  /// Has the server evaluate [candidates], as corrected, again.
  ServiceResult<List<ManualImportCandidate>> reprocess(
    List<ManualImportCandidate> candidates, {
    required ServarrImportMapping mapping,
  }) async {
    if (candidates.isEmpty) return const Ok([]);
    final List<JsonObject> entries;
    switch (await _entries(candidates, mapping)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        entries = value;
    }
    final sent = {
      for (final candidate in candidates) candidate.path: candidate,
    };
    return _client._send(
      HttpMethod.post,
      'manualimport',
      (json) => [
        for (final record in asObjects(json))
          reprocessedCandidate(
            sent[requireString(record, 'path')] ??
                (throw const FormatException('A file that was not sent')),
            record,
            mapping,
          ),
      ],
      body: JsonBody([
        for (final (index, candidate) in candidates.indexed)
          {'id': ?candidate.rawJson['id'], ...entries[index]},
      ]),
    );
  }

  /// Imports every one of [candidates], whether marked as selected or not, and
  /// gives the command to follow with [ServarrClient.commandStatus].
  ///
  /// With no candidates nothing is sent and the result is [Validation]. Where
  /// a quality was corrected, here or in [reprocess], its definition is read
  /// first: if that fails, or the server does not have the quality
  /// ([NotFound]), nothing is written.
  ServiceResult<Command> importFiles(
    List<ManualImportCandidate> candidates, {
    required ServarrImportMapping mapping,
  }) async {
    if (candidates.isEmpty) return const Err(Validation([]));
    final List<JsonObject> entries;
    switch (await _entries(candidates, mapping)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        entries = value;
    }
    return _client._send(
      HttpMethod.post,
      'command',
      (json) => readCommand(asObject(json)),
      body: JsonBody({
        'name': 'ManualImport',
        'importMode': 'auto',
        'files': [
          for (final (index, candidate) in candidates.indexed)
            {...entries[index], 'folderName': ?candidate.rawJson['folderName']},
        ],
      }),
    );
  }

  /// The [importEntry] of each of [candidates].
  ServiceResult<List<JsonObject>> _entries(
    List<ManualImportCandidate> candidates,
    ServarrImportMapping mapping,
  ) async {
    final corrected = {
      for (final candidate in candidates) ?correctedQualityId(candidate),
    };
    var qualities = const <int, JsonObject>{};
    if (corrected.isNotEmpty) {
      switch (await _client.read(
        'qualitydefinition',
        (json) => Map.fromEntries(asObjects(json).map(qualityById)),
      )) {
        case Err(:final error):
          return Err(error);
        case Ok(:final value):
          qualities = value;
      }
      if (!corrected.every(qualities.containsKey)) {
        return const Err(NotFound());
      }
    }
    return Ok([
      for (final candidate in candidates)
        importEntry(candidate, mapping, qualities),
    ]);
  }

  /// A write whose answer is not read.
  ServiceResult<void> _write(
    HttpMethod method,
    String path, {
    Map<String, List<String>> query = const {},
    RequestBody? body,
  }) async {
    final request = ServiceRequest(
      method,
      '${_client._apiPath}/$path',
      query: query,
      body: body,
    );
    return switch (await _client._http.send(request)) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error.failure),
    };
  }

  // `removeFromClient` is stated, as the server removes unless told not to.
  Map<String, List<String>> _removal(RemoveOptions options) => {
    'removeFromClient': ['${options.removeFromClient}'],
    'blocklist': ['${options.blocklist}'],
    if (options.blocklist) 'skipRedownload': ['${!options.searchReplacement}'],
  };
}
