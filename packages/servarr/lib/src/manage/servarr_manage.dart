part of '../servarr_client.dart';

/// How long the answer to an interactive search is waited for. The server asks
/// its indexers while the request is open, and gives each of them up to 100
/// seconds.
const _searchTimeout = Duration(minutes: 2);

/// The fields of a search target that a grab may send. The server takes further
/// ones that change what it does with a release.
const _grabTargetFields = ['movieId', 'episodeId', 'seriesId', 'seasonNumber'];

/// Interactive search and grab, commands, and edits.
///
/// A write is sent once. What a successful one answers is not read, but for
/// [grab] and [startCommand]: one the server accepted with an answer that
/// cannot be understood is [OutcomeUnknown].
mixin _ServarrManage on _ServarrActivity {
  /// The releases the indexers have for [target], the query that names it,
  /// such as `{'movieId': 1}`, in the server's order. Each keeps [target] as
  /// its [Release.searchTarget].
  ///
  /// Without a target the server answers with its RSS feeds, so an empty one
  /// sends nothing and fails with [Validation].
  ServiceResult<List<Release>> releases(Map<String, int> target) async {
    if (target.isEmpty) return const Err(Validation([]));
    // A copy, as the caller may change its own.
    final searched = Map<String, int>.unmodifiable(target);
    return _client._send(
      HttpMethod.get,
      'release',
      (json) => [
        for (final record in asObjects(json)) releaseRecord(record, searched),
      ],
      query: {
        for (final MapEntry(:key, :value) in searched.entries) key: ['$value'],
      },
      timeout: _searchTimeout,
    );
  }

  /// What the indexers have for a free-text search, which [query] names, at
  /// `GET search` as Prowlarr has it, in the server's order. It is waited for
  /// as long as [releases] are.
  ///
  /// The server answers a search without a term with its indexers' feeds, so
  /// [query] is the caller's to check.
  ServiceResult<List<Release>> textSearch(Map<String, List<String>> query) =>
      _client._send(
        HttpMethod.get,
        'search',
        (json) => [
          for (final record in asObjects(json)) releaseRecord(record, const {}),
        ],
        query: query,
        timeout: _searchTimeout,
      );

  /// Has the server download [release], rejected or not. [path] is where the
  /// release was found: `release`, or `search` for a [textSearch].
  ///
  /// A release the server could not match ([Release.downloadAllowed]) is sent
  /// with its [Release.searchTarget], as the web UI does once the user has
  /// confirmed: the server then takes it to be what was searched for.
  ServiceResult<void> grab(Release release, {String path = 'release'}) =>
      _accepted(
        path,
        asObject,
        JsonBody({
          'guid': release.guid,
          'indexerId': release.indexerId,
          if (!release.downloadAllowed)
            for (final field in _grabTargetFields)
              field: ?release.searchTarget[field],
        }),
      );

  /// Starts the command [name] on [target], the fields that say what it acts
  /// on, and gives the command to follow with [ServarrClient.commandStatus].
  ///
  /// Some commands act on the whole library without them, so an empty target,
  /// or an empty list in it, sends nothing and fails with [Validation].
  ServiceResult<Command> startCommand(String name, JsonObject target) async {
    if (target.isEmpty ||
        target.values.any((value) => value is List && value.isEmpty)) {
      return const Err(Validation([]));
    }
    return _accepted(
      'command',
      (json) => readCommand(asObject(json)),
      JsonBody({'name': name, ...target}),
    );
  }

  /// Reads the record at [path], lets [change] alter it and writes the whole
  /// of it back to [path] (research R13). A [FormatException] of [change], for
  /// a record it cannot understand, is [MalformedResponse], and nothing is
  /// written.
  ServiceResult<void> update(
    String path,
    void Function(JsonObject record) change,
  ) async {
    final read = await _client.read(path, (json) {
      final record = asObject(json);
      change(record);
      return record;
    });
    return switch (read) {
      Err(:final error) => Err(error),
      Ok(:final value) => await _write(
        HttpMethod.put,
        path,
        body: JsonBody(value),
      ),
    };
  }

  /// [update] with the fields set in [changes]. An `unknown` series type or
  /// minimum availability is not a value to write. With nothing to write,
  /// nothing is sent.
  ServiceResult<void> edit(String path, ItemEdit changes) async {
    final fields = <String, Object?>{
      'monitored': ?changes.monitored,
      'qualityProfileId': ?changes.qualityProfileId,
      'metadataProfileId': ?changes.metadataProfileId,
      'tags': ?changes.tagIds?.toList(),
      if (changes.seriesType case final type? when type != SeriesType.unknown)
        'seriesType': type.name,
      'seasonFolder': ?changes.seasonFolder,
      if (changes.minimumAvailability case final availability?
          when availability != MinimumAvailability.unknown)
        'minimumAvailability': availability.name,
    };
    if (fields.isEmpty) return const Ok(null);
    return update(path, (record) => record.addAll(fields));
  }

  /// Changes the items [ids] through the editor at [path], which names them
  /// [idsField]. With no ids or nothing to change, nothing is sent.
  ServiceResult<void> bulkEdit(
    String path, {
    required String idsField,
    required List<int> ids,
    required BulkEdit changes,
  }) async {
    final tags = changes.tagIds;
    final fields = <String, Object?>{
      'monitored': ?changes.monitored,
      'qualityProfileId': ?changes.qualityProfileId,
      // No tags to add or remove change nothing; none to replace with do.
      if (tags != null &&
          (tags.isNotEmpty || changes.tagChange == TagChange.replace)) ...{
        'tags': tags.toList(),
        'applyTags': changes.tagChange.name,
      },
    };
    if (ids.isEmpty || fields.isEmpty) return const Ok(null);
    return _write(
      HttpMethod.put,
      path,
      body: JsonBody({idsField: ids, ...fields}),
    );
  }

  /// A `POST` whose answer says what the server accepted.
  ServiceResult<T> _accepted<T>(
    String path,
    T Function(Object? json) decode,
    RequestBody body,
  ) async {
    final result = await _client._send(
      HttpMethod.post,
      path,
      decode,
      body: body,
    );
    // The server has the request, so it cannot be said to have failed.
    return switch (result) {
      Err(error: MalformedResponse()) => const Err(OutcomeUnknown()),
      _ => result,
    };
  }
}
