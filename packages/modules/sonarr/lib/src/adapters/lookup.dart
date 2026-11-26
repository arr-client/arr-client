/// Searching for series and adding them.
library;

import 'package:core/core.dart';

import '../api/sonarr_api.dart';
import '../models/json_fields.dart';
import '../models/media_record.dart';
import 'monitor_options.dart';

/// New series.
final class SonarrLookupAdapter implements LookupProvider {
  /// Searches and adds with [_api].
  SonarrLookupAdapter(this._api);

  final SonarrApi _api;

  @override
  Set<MediaKind> get itemKinds => const {MediaKind.series};

  @override
  ServiceResult<List<AddCandidate>> lookup(String term) async {
    // There is nothing to search for.
    if (term.trim().isEmpty) return const Ok([]);
    switch (await _api.lookup(term)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        try {
          return Ok(value.map(_candidate).toList());
        } on FormatException {
          // The exception may quote a record, so it goes no further.
          return const Err(MalformedResponse());
        }
    }
  }

  @override
  ServiceResult<AddCandidate> find(AddCandidate candidate) {
    _requireSeries(candidate.kind);
    return _find(candidate);
  }

  @override
  ServiceResult<AddOptions> addOptions(MediaKind kind) {
    _requireSeries(kind);
    return _addOptions();
  }

  /// Posts the record this instance's search gave, or the one it gives now for
  /// the TVDB id, with the choices set in it.
  ///
  /// A series the instance has is a [Conflict]. A root folder it no longer has
  /// is [Validation], and nothing is sent. Without a choice of season folders
  /// they are used, as by default in Sonarr's own form.
  @override
  ServiceResult<ItemRef> add(AddCandidate candidate, AddChoices choices) {
    _requireSeries(candidate.kind);
    return _add(candidate, choices);
  }

  ServiceResult<AddCandidate> _find(AddCandidate candidate) async {
    switch (await _lookupAgain(candidate)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        try {
          return Ok(_candidate(value));
        } on FormatException {
          // The exception may quote the record, so it goes no further.
          return const Err(MalformedResponse());
        }
    }
  }

  ServiceResult<AddOptions> _addOptions() async => switch (await _api
      .options()) {
    Ok(:final value) => Ok(
      AddOptions(serverOptions: value, monitorOptions: sonarrMonitorOptions),
    ),
    Err(:final error) => Err(error),
  };

  ServiceResult<ItemRef> _add(
    AddCandidate candidate,
    AddChoices choices,
  ) async {
    final JsonObject record;
    switch (await _record(candidate)) {
      case Ok(:final value):
        record = value;
      case Err(:final error):
        return Err(error);
    }
    // Only a series the server has carries an id.
    if (optionalPositive(record, 'id') != null) return const Err(Conflict());

    final String rootFolder;
    switch (await _rootFolderPath(choices.rootFolderId)) {
      case Ok(:final value):
        rootFolder = value;
      case Err(:final error):
        return Err(error);
    }

    // A copy: the candidate may be added to another instance too.
    final series = <String, Object?>{
      ...record,
      'rootFolderPath': rootFolder,
      'qualityProfileId': choices.qualityProfileId,
      if (choices.seriesType case final type? when type != SeriesType.unknown)
        'seriesType': type.name,
      // Never left as found: a search result says false.
      'seasonFolder': choices.seasonFolder ?? true,
      'tags': choices.tagIds.toList(),
      // As Sonarr's form does; the option decides which episodes are monitored.
      'monitored': true,
      'addOptions': <String, Object?>{
        'monitor': choices.monitorOptionId,
        'searchForMissingEpisodes': choices.searchNow,
        'searchForCutoffUnmetEpisodes': false,
      },
    };
    return switch (await _api.addSeries(series)) {
      Ok(:final value) => Ok(_api.seriesRef(value)),
      Err(:final error) => Err(error),
    };
  }

  /// The lookup result of this instance for [candidate].
  ServiceResult<JsonObject> _record(AddCandidate candidate) async {
    final own = candidate.sourceByInstance[_api.instanceId];
    if (own != null) return Ok(own);
    return _lookupAgain(candidate);
  }

  /// What the instance gives now for the TVDB id of [candidate].
  ServiceResult<JsonObject> _lookupAgain(AddCandidate candidate) async {
    final tvdbId = candidate.externalIds.tvdbId;
    if (tvdbId == null) return const Err(NotFound());
    switch (await _api.lookup('tvdb:$tvdbId')) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        for (final record in value) {
          if (record['tvdbId'] == tvdbId) return Ok(record);
        }
        return const Err(NotFound());
    }
  }

  /// The path of the root folder [id], read now: the choice may be an old one.
  ServiceResult<String> _rootFolderPath(int id) async {
    switch (await _api.rootFolders()) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        for (final folder in value) {
          if (folder['id'] != id) continue;
          return switch (optionalText(folder, 'path')) {
            final path? => Ok(path),
            null => const Err(MalformedResponse()),
          };
        }
        // Nothing was sent, so the server has no message for it.
        return const Err(Validation([]));
    }
  }

  /// A record of `GET series/lookup`.
  AddCandidate _candidate(JsonObject record) {
    final id = optionalPositive(record, 'id');
    return AddCandidate(
      kind: MediaKind.series,
      title: requireText(record, 'title'),
      externalIds: ExternalIds(
        tvdbId: optionalPositive(record, 'tvdbId'),
        tmdbId: optionalPositive(record, 'tmdbId'),
        imdbId: optionalText(record, 'imdbId'),
      ),
      year: optionalPositive(record, 'year'),
      overview: optionalText(record, 'overview'),
      images: readImages(record['images']),
      existingRefs: [if (id != null) _api.seriesRef(id)],
      sourceByInstance: {_api.instanceId: record},
    );
  }
}

void _requireSeries(MediaKind kind) {
  if (kind != MediaKind.series) {
    throw ArgumentError.value(kind, 'kind', 'Sonarr adds series only');
  }
}
