/// Searching for artists and albums and adding them.
library;

import 'package:core/core.dart';

import '../api/lidarr_api.dart';
import '../models/json_fields.dart';
import '../models/library_record.dart';
import '../models/media_record.dart';
import 'monitor_options.dart';

/// New artists and albums.
final class LidarrLookupAdapter implements LookupProvider {
  /// Searches and adds with [_api].
  LidarrLookupAdapter(this._api);

  final LidarrApi _api;

  @override
  Set<MediaKind> get itemKinds => const {MediaKind.artist, MediaKind.album};

  /// The artists found, then the albums. Fails if either search does.
  @override
  ServiceResult<List<AddCandidate>> lookup(String term) async {
    // There is nothing to search for.
    if (term.trim().isEmpty) return const Ok([]);
    // Both at once: each asks the server's metadata source.
    final (artists, albums) = await (
      _search(MediaKind.artist, term),
      _search(MediaKind.album, term),
    ).wait;
    final found = <AddCandidate>[];
    for (final (kind, result) in [
      (MediaKind.artist, artists),
      (MediaKind.album, albums),
    ]) {
      switch (result) {
        case Err(:final error):
          return Err(error);
        case Ok(:final value):
          try {
            found.addAll([
              for (final record in value) _candidate(kind, record),
            ]);
          } on FormatException {
            // The exception may quote a record, so it goes no further.
            return const Err(MalformedResponse());
          }
      }
    }
    return Ok(found);
  }

  @override
  ServiceResult<AddCandidate> find(AddCandidate candidate) {
    _requireAddable(candidate.kind);
    return _find(candidate);
  }

  @override
  ServiceResult<AddOptions> addOptions(MediaKind kind) {
    _requireAddable(kind);
    return _addOptions();
  }

  /// Posts the record this instance's search gave, or the one it gives now for
  /// the MusicBrainz id, with the choices set in it.
  ///
  /// An album brings its artist along. One the instance does not have is made
  /// with the choices; one it has is sent as found, and of the choices only
  /// `searchNow` then applies.
  ///
  /// An item the instance has is a [Conflict]. A root folder it no longer has
  /// is [Validation], and nothing is sent.
  @override
  ServiceResult<ItemRef> add(AddCandidate candidate, AddChoices choices) {
    _requireAddable(candidate.kind);
    return _add(candidate, choices);
  }

  ServiceResult<AddCandidate> _find(AddCandidate candidate) async {
    switch (await _lookupAgain(candidate)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        try {
          return Ok(_candidate(candidate.kind, value));
        } on FormatException {
          // The exception may quote the record, so it goes no further.
          return const Err(MalformedResponse());
        }
    }
  }

  ServiceResult<AddOptions> _addOptions() async => switch (await _api
      .options()) {
    Ok(:final value) => Ok(
      AddOptions(serverOptions: value, monitorOptions: lidarrMonitorOptions),
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
    // Only an item the server has carries an id.
    if (optionalPositive(record, 'id') != null) return const Err(Conflict());
    return candidate.kind == MediaKind.artist
        ? _addArtist(record, choices)
        : _addAlbum(record, choices);
  }

  ServiceResult<ItemRef> _addArtist(
    JsonObject record,
    AddChoices choices,
  ) async {
    final JsonObject artist;
    switch (await _newArtist(record, choices, search: choices.searchNow)) {
      case Ok(:final value):
        artist = value;
      case Err(:final error):
        return Err(error);
    }
    return switch (await _api.addArtist(artist)) {
      Ok(:final value) => Ok(_api.artistRef(value)),
      Err(:final error) => Err(error),
    };
  }

  ServiceResult<ItemRef> _addAlbum(
    JsonObject record,
    AddChoices choices,
  ) async {
    var artist = objectIn(record, 'artist');
    if (artist.isEmpty) return const Err(MalformedResponse());
    if (optionalPositive(artist, 'id') == null) {
      // No search for the artist: the server would search for all of it, where
      // only this album was asked for.
      switch (await _newArtist(artist, choices, search: false)) {
        case Ok(:final value):
          artist = value;
        case Err(:final error):
          return Err(error);
      }
    }
    // A copy: the candidate may be added to another instance too.
    final album = <String, Object?>{
      ...record,
      'artist': artist,
      'monitored': true,
      'addOptions': <String, Object?>{'searchForNewAlbum': choices.searchNow},
    };
    return switch (await _api.addAlbum(album)) {
      Ok(:final value) => Ok(_api.albumRef(value)),
      Err(:final error) => Err(error),
    };
  }

  /// A copy of [record], an artist the server does not have, as it is posted.
  ServiceResult<JsonObject> _newArtist(
    JsonObject record,
    AddChoices choices, {
    required bool search,
  }) async {
    final String rootFolder;
    switch (await _rootFolderPath(choices.rootFolderId)) {
      case Ok(:final value):
        rootFolder = value;
      case Err(:final error):
        return Err(error);
    }
    return Ok({
      ...record,
      'rootFolderPath': rootFolder,
      'qualityProfileId': choices.qualityProfileId,
      'metadataProfileId': ?choices.metadataProfileId,
      'tags': choices.tagIds.toList(),
      // As Lidarr's form does; the option decides which albums are monitored.
      'monitored': true,
      'addOptions': <String, Object?>{
        'monitor': choices.monitorOptionId,
        'searchForMissingAlbums': search,
      },
    });
  }

  /// The lookup result of this instance for [candidate].
  ServiceResult<JsonObject> _record(AddCandidate candidate) async {
    final own = candidate.sourceByInstance[_api.instanceId];
    if (own != null) return Ok(own);
    return _lookupAgain(candidate);
  }

  /// What the instance gives now for the MusicBrainz id of [candidate].
  ServiceResult<JsonObject> _lookupAgain(AddCandidate candidate) async {
    final id = candidate.externalIds.musicBrainzId;
    if (id == null) return const Err(NotFound());
    switch (await _search(candidate.kind, 'lidarr:$id')) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        for (final record in value) {
          if (record[_foreignIdField(candidate.kind)] == id) return Ok(record);
        }
        return const Err(NotFound());
    }
  }

  ServiceResult<List<JsonObject>> _search(MediaKind kind, String term) =>
      kind == MediaKind.artist
      ? _api.lookupArtists(term)
      : _api.lookupAlbums(term);

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

  /// A record of `GET artist/lookup` or `GET album/lookup`.
  AddCandidate _candidate(MediaKind kind, JsonObject record) {
    final isArtist = kind == MediaKind.artist;
    final id = optionalPositive(record, 'id');
    return AddCandidate(
      kind: kind,
      title: requireText(record, isArtist ? 'artistName' : 'title'),
      parentTitle: isArtist ? null : embeddedArtistName(record),
      externalIds: ExternalIds(
        musicBrainzId: optionalText(record, _foreignIdField(kind)),
      ),
      year: isArtist ? null : optionalTime(record, 'releaseDate')?.year,
      overview: optionalText(record, 'overview'),
      images: readImages(record['images']),
      existingRefs: [
        if (id != null) isArtist ? _api.artistRef(id) : _api.albumRef(id),
      ],
      sourceByInstance: {_api.instanceId: record},
    );
  }
}

// The MusicBrainz id.
String _foreignIdField(MediaKind kind) =>
    kind == MediaKind.artist ? 'foreignArtistId' : 'foreignAlbumId';

void _requireAddable(MediaKind kind) {
  if (kind != MediaKind.artist && kind != MediaKind.album) {
    throw ArgumentError.value(kind, 'kind', 'Lidarr adds artists and albums');
  }
}
