import 'dart:convert';

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../models/json_fields.dart';

const _apiPath = 'api/v1';

/// Lidarr's requests for one instance.
///
/// As in [ServarrClient], a failure of the HTTP client is returned unchanged,
/// nothing is retried, and an answer of another shape is [MalformedResponse].
final class LidarrApi {
  /// The API of the instance of [context].
  LidarrApi(InstanceContext context)
    : instanceId = context.instance.id,
      _http = context.http,
      shared = ServarrClient(
        context.http,
        apiPath: _apiPath,
        includeUnknownParameter: 'includeUnknownArtistItems',
        refs: (record) => _refs(context.instance.id, record),
        hasMetadataProfiles: true,
      );

  /// The instance whose items the records are.
  final String instanceId;

  /// The client for what the family shares as it is.
  final ServarrClient shared;

  final ServiceHttpClient _http;

  /// The key of the artist [id].
  ItemRef artistRef(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.artist, remoteId: id);

  /// The key of the album [id].
  ItemRef albumRef(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.album, remoteId: id);

  /// The key of the track [id].
  ItemRef trackRef(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.track, remoteId: id);

  /// Every artist, as received.
  ServiceResult<List<JsonObject>> artists() => shared.read('artist', asObjects);

  /// One artist, as received.
  ServiceResult<JsonObject> artist(int id) =>
      shared.read('artist/$id', asObject);

  /// The albums of an artist, each with its artist. An artist the server does
  /// not have gets an empty list.
  ServiceResult<List<JsonObject>> albums(int artistId) =>
      shared.read('album', asObjects, query: _ofArtist(artistId));

  /// One album, with its artist.
  ServiceResult<JsonObject> album(int id) => shared.read('album/$id', asObject);

  /// The tracks of an album. An album the server does not have gets an empty
  /// list.
  ServiceResult<List<JsonObject>> tracks(int albumId) =>
      shared.read('track', asObjects, query: _ofAlbum(albumId));

  /// The track files of an artist.
  ServiceResult<List<JsonObject>> artistFiles(int artistId) =>
      shared.read('trackfile', asObjects, query: _ofArtist(artistId));

  /// The track files of an album.
  ServiceResult<List<JsonObject>> albumFiles(int albumId) =>
      shared.read('trackfile', asObjects, query: _ofAlbum(albumId));

  /// The artists the server's metadata source finds for [term], which may be
  /// `lidarr:<MusicBrainz id>`. One the server has carries its id.
  ServiceResult<List<JsonObject>> lookupArtists(String term) =>
      shared.read('artist/lookup', asObjects, query: _ofTerm(term));

  /// As [lookupArtists], for albums, each with its artist.
  ServiceResult<List<JsonObject>> lookupAlbums(String term) =>
      shared.read('album/lookup', asObjects, query: _ofTerm(term));

  /// The root folders, as received.
  ServiceResult<List<JsonObject>> rootFolders() =>
      shared.read('rootfolder', asObjects);

  /// Adds [artist], sending it once, and gives its id. If the server accepts it
  /// without saying which artist it made, that is [OutcomeUnknown].
  ServiceResult<int> addArtist(JsonObject artist) =>
      _add('artist', artist, existsCode: 'ArtistExistsValidator');

  /// As [addArtist], for an album with its artist.
  ServiceResult<int> addAlbum(JsonObject album) =>
      _add('album', album, existsCode: 'AlbumExistsValidator');

  /// The whole download queue.
  ServiceResult<List<QueueItem>> queue() => shared.queue();

  /// Quality and metadata profiles, root folders and tags.
  ServiceResult<List<ServerOption>> options() => shared.options();

  ServiceResult<int> _add(
    String path,
    JsonObject record, {
    required String existsCode,
  }) async {
    final request = ServiceRequest(
      HttpMethod.post,
      '$_apiPath/$path',
      body: JsonBody(record),
    );
    switch (await _http.send(request)) {
      case Err(:final error):
        return Err(
          _refusedBy(error, existsCode) ? const Conflict() : error.failure,
        );
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

  static Map<String, List<String>> _ofArtist(int id) => {
    'artistId': ['$id'],
  };

  static Map<String, List<String>> _ofAlbum(int id) => {
    'albumId': ['$id'],
  };

  static Map<String, List<String>> _ofTerm(String term) => {
    'term': [term],
  };
}

/// Whether a refused add names the validator [code]. Other refusals, a folder
/// already in use included, stay as they are.
bool _refusedBy(HttpError error, String code) {
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
        (refusal) => refusal is JsonObject && refusal['errorCode'] == code,
      );
}

/// A queue or history record is about an album of an artist.
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
    item: ref(MediaKind.album, 'albumId'),
    parent: ref(MediaKind.artist, 'artistId'),
  );
}
