import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import '../api/radarr_api.dart';
import '../l10n/generated/radarr_localizations.dart';
import '../models/movie_record.dart';

// The values of `addOptions.monitor`.
const _monitorNone = 'none';
const _monitorOptions = [
  MonitorOption(id: 'movieOnly', label: _movieOnlyLabel),
  MonitorOption(id: 'movieAndCollection', label: _movieAndCollectionLabel),
  MonitorOption(id: _monitorNone, label: _noneLabel),
];

String _movieOnlyLabel(BuildContext context) =>
    RadarrLocalizations.of(context).monitorMovieOnly;

String _movieAndCollectionLabel(BuildContext context) =>
    RadarrLocalizations.of(context).monitorMovieAndCollection;

String _noneLabel(BuildContext context) =>
    RadarrLocalizations.of(context).monitorNone;

// The rule Radarr names when it refuses a movie it already has.
const _existsCode = 'MovieExistsValidator';

/// Searching for movies and adding them to one Radarr instance.
final class RadarrLookupAdapter implements LookupProvider {
  /// Reads and adds through [_api], on the instance [_instanceId].
  RadarrLookupAdapter(this._api, this._instanceId);

  final RadarrApi _api;
  final String _instanceId;

  @override
  Set<MediaKind> get itemKinds => const {MediaKind.movie};

  @override
  ServiceResult<List<AddCandidate>> lookup(String term) async {
    if (term.trim().isEmpty) return const Ok([]);
    switch (await _api.lookup(term)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        try {
          return Ok([
            for (final record in value)
              readCandidate(record, instanceId: _instanceId),
          ]);
        } on FormatException {
          // The exception may quote the record, so it goes no further.
          return const Err(MalformedResponse());
        }
    }
  }

  @override
  ServiceResult<AddOptions> addOptions(MediaKind kind) async {
    _checkKind(kind);
    return switch (await _api.options()) {
      Ok(:final value) => Ok(
        AddOptions(serverOptions: value, monitorOptions: _monitorOptions),
      ),
      Err(:final error) => Err(error),
    };
  }

  @override
  ServiceResult<ItemRef> add(AddCandidate candidate, AddChoices choices) async {
    _checkKind(candidate.kind);
    final JsonObject record;
    switch (await _record(candidate)) {
      case Ok(:final value):
        record = value;
      case Err(:final error):
        return Err(error);
    }
    if (libraryId(record) != null) return const Err(Conflict());
    final String rootFolder;
    switch (await _rootFolderPath(choices.rootFolderId)) {
      case Ok(:final value):
        rootFolder = value;
      case Err(:final error):
        return Err(error);
    }
    // A copy: the candidate may be added to another instance too.
    final movie = <String, Object?>{
      ...record,
      'rootFolderPath': rootFolder,
      'qualityProfileId': choices.qualityProfileId,
      'tags': choices.tagIds.toList(),
      // Without a choice the record keeps its own.
      if (choices.minimumAvailability case final chosen?
          when chosen != MinimumAvailability.unknown)
        'minimumAvailability': chosen.name,
      'monitored': choices.monitorOptionId != _monitorNone,
      'addOptions': {
        'monitor': choices.monitorOptionId,
        'searchForMovie': choices.searchNow,
      },
    };
    return switch (await _api.addMovie(movie)) {
      Ok(:final value) => _added(value),
      Err(:final error) => Err(
        _alreadyExists(error) ? const Conflict() : error.failure,
      ),
    };
  }

  /// What to post for [candidate]: this instance's own result, or else the one
  /// it gives now for the TMDB id. Another server's record is never posted.
  ServiceResult<JsonObject> _record(AddCandidate candidate) async {
    if (candidate.sourceByInstance[_instanceId] case final own?) return Ok(own);
    final tmdbId = candidate.externalIds.tmdbId;
    if (tmdbId == null) return const Err(NotFound());
    switch (await _api.lookup('tmdb:$tmdbId')) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        for (final record in value) {
          if (record['tmdbId'] == tmdbId) return Ok(record);
        }
        return const Err(NotFound());
    }
  }

  /// The path of the root folder [id]. The server may have dropped it since the
  /// user chose it, which is [Validation].
  ServiceResult<String> _rootFolderPath(int id) async {
    switch (await _api.rootFolders()) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        for (final folder in value) {
          if (folder['id'] != id) continue;
          return switch (folder['path']) {
            final String path when path.isNotEmpty => Ok(path),
            _ => const Err(MalformedResponse()),
          };
        }
        return const Err(Validation([]));
    }
  }

  /// The movie the server says it made. It accepted the add, so an answer that
  /// does not name one leaves the outcome unknown.
  Result<ItemRef, ServiceFailure> _added(ServiceResponse response) {
    Object? movie;
    try {
      movie = jsonDecode(response.text);
    } on FormatException {
      // The exception quotes the body, so it goes no further.
      movie = null;
    }
    final id = movie is JsonObject ? libraryId(movie) : null;
    if (id == null) return const Err(OutcomeUnknown());
    return Ok(
      ItemRef(instanceId: _instanceId, kind: MediaKind.movie, remoteId: id),
    );
  }

  /// Whether the server refused the add because it has the movie.
  static bool _alreadyExists(HttpError error) {
    final response = error.response;
    if (error.failure is! Validation || response == null) return false;
    final Object? reasons;
    try {
      reasons = jsonDecode(response.text);
    } on FormatException {
      return false;
    }
    return reasons is List<Object?> &&
        reasons.any(
          (reason) => switch (reason) {
            {'errorCode': _existsCode} => true,
            _ => false,
          },
        );
  }

  static void _checkKind(MediaKind kind) {
    if (kind != MediaKind.movie) {
      throw ArgumentError.value(kind, 'kind', 'Radarr adds movies only');
    }
  }
}
