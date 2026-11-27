/// Reading the records of Seerr, Overseerr and Jellyseerr. What a record cannot
/// do without throws [FormatException].
///
/// Users come with their password hashes and addresses, of which only the id
/// and the name to show are read. Bodies are never logged.
library;

import 'package:core/core.dart';

import '../api/refusals.dart';
import '../api/seerr_api.dart';
import 'server.dart';

// Posters are about this wide on the screens.
const _posterSize = 'w500';

// A path below the image host: nothing that could lead elsewhere on the
// instance, whose requests carry the credential.
final _posterPath = RegExp(r'^(/[A-Za-z0-9_-][A-Za-z0-9._-]*)+$');

/// [value] as an object.
JsonObject asObject(Object? value) =>
    value is JsonObject ? value : throw const FormatException('Not an object');

/// [value] as a list of objects.
List<JsonObject> asObjects(Object? value) => value is List<Object?>
    ? [for (final entry in value) asObject(entry)]
    : throw const FormatException('Not a list');

/// The whole number in [field].
int requireInt(JsonObject object, String field) => switch (object[field]) {
  final int value => value,
  _ => throw const FormatException('A number is missing'),
};

String _requireString(JsonObject object, String field) =>
    switch (object[field]) {
      final String value => value,
      _ => throw const FormatException('A text is missing'),
    };

DateTime _requireTime(JsonObject object, String field) =>
    DateTime.parse(_requireString(object, field));

/// What [read] makes of a record, or [MalformedResponse].
Result<T, ServiceFailure> reading<T>(T Function() read) {
  try {
    return Ok(read());
  } on FormatException {
    // The exception may quote the body, so it goes no further.
    return const Err(MalformedResponse());
  }
}

/// The object that [response] holds, read by [read].
Result<T, ServiceFailure> decode<T>(
  ServiceResponse response,
  T Function(JsonObject object) read,
) => reading(() => read(asObject(jsonObjectOf(response))));

/// `GET api/v1/[path]`, read by [read].
ServiceResult<T> readRecord<T>(
  SeerrApi api,
  String path,
  T Function(JsonObject object) read, {
  Map<String, List<String>> query = const {},
}) async => switch (await api.read(path, query: query)) {
  Err(:final error) => Err(error.failure),
  Ok(:final value) => decode(value, read),
};

/// The movie or series that a `mediaType` names, and null for what is neither,
/// such as a person.
DiscoveryMediaType? mediaTypeOf(Object? name) => switch (name) {
  'movie' => DiscoveryMediaType.movie,
  'tv' => DiscoveryMediaType.series,
  _ => null,
};

/// What the API calls [type], in paths and bodies.
String wireName(DiscoveryMediaType type) => switch (type) {
  DiscoveryMediaType.movie => 'movie',
  DiscoveryMediaType.series => 'tv',
};

/// The name of a movie or series.
String titleName(JsonObject object, DiscoveryMediaType type) =>
    _requireString(object, type == DiscoveryMediaType.movie ? 'title' : 'name');

/// One title, from a list or from its own page. [cacheImages] says whether the
/// instance serves its posters; null leaves them out.
DiscoveryTitle discoveryTitle(
  JsonObject object,
  DiscoveryMediaType type, {
  required SeerrServer server,
  required bool? cacheImages,
}) {
  // Only for a title the server knows.
  final media = switch (object['mediaInfo']) {
    null => null,
    final info => asObject(info),
  };
  // Only a title's own page carries its requests.
  final requests = switch (media?['requests']) {
    null => const <JsonObject>[],
    final list => asObjects(list),
  };
  final date =
      object[type == DiscoveryMediaType.movie ? 'releaseDate' : 'firstAirDate'];
  final externalIds = object['externalIds'];
  final tvdbId =
      (externalIds is JsonObject ? externalIds['tvdbId'] : null) ??
      media?['tvdbId'];
  return DiscoveryTitle(
    tmdbId: requireInt(object, 'id'),
    mediaId: media == null ? null : requireInt(media, 'id'),
    mediaType: type,
    title: titleName(object, type),
    tvdbId: tvdbId is int ? tvdbId : null,
    year: date is String && date.length >= 4
        ? int.tryParse(date.substring(0, 4))
        : null,
    poster: _poster(object['posterPath'], server, cacheImages),
    availability: server.availability(media?['status']),
    availability4k: server.availability(media?['status4k']),
    requestStatus: _newestStatus(requests, is4k: false),
    requestStatus4k: _newestStatus(requests, is4k: true),
  );
}

MediaImage? _poster(Object? path, SeerrServer server, bool? cacheImages) {
  if (cacheImages == null || path is! String || !_posterPath.hasMatch(path)) {
    return null;
  }
  return cacheImages
      ? MediaImage(
          type: MediaImageType.poster,
          instancePath: server.proxiedPoster(_posterSize, path),
        )
      : MediaImage(
          type: MediaImageType.poster,
          remoteUrl: Uri.https('image.tmdb.org', 't/p/$_posterSize$path'),
        );
}

// A variant may have been asked for several times; the highest id is the last.
RequestStatus? _newestStatus(List<JsonObject> requests, {required bool is4k}) {
  JsonObject? newest;
  for (final request in requests) {
    if ((request['is4k'] == true) == is4k &&
        (newest == null ||
            requireInt(request, 'id') > requireInt(newest, 'id'))) {
      newest = request;
    }
  }
  return newest == null ? null : _requestStatus(newest['status']);
}

RequestStatus _requestStatus(Object? number) => switch (number) {
  1 => RequestStatus.pending,
  2 => RequestStatus.approved,
  3 => RequestStatus.declined,
  4 => RequestStatus.failed,
  5 => RequestStatus.completed,
  _ => RequestStatus.unknown,
};

/// The id and the name to show of a user.
ServiceUser serviceUser(Object? value) {
  final user = asObject(value);
  final name = user['displayName'];
  return ServiceUser(
    id: requireInt(user, 'id'),
    name: name is String ? name : '',
  );
}

DiscoveryRef _mediaRef(JsonObject media) => DiscoveryRef(
  mediaType:
      mediaTypeOf(media['mediaType']) ??
      (throw const FormatException('Not a movie or series')),
  tmdbId: requireInt(media, 'tmdbId'),
);

/// One request.
MediaRequest mediaRequest(JsonObject object, SeerrServer server) {
  final media = asObject(object['media']);
  final is4k = object['is4k'] == true;
  return MediaRequest(
    id: requireInt(object, 'id'),
    titleRef: _mediaRef(media),
    requestedBy: serviceUser(object['requestedBy']),
    status: _requestStatus(object['status']),
    availability: server.availability(media[is4k ? 'status4k' : 'status']),
    is4k: is4k,
    // A new request for a movie has none at all.
    seasons: switch (object['seasons']) {
      null => const [],
      final seasons => [
        for (final season in asObjects(seasons))
          requireInt(season, 'seasonNumber'),
      ],
    },
  );
}

/// The title that an issue is about.
DiscoveryRef issueRef(JsonObject issue) => _mediaRef(asObject(issue['media']));

/// One issue. An issue names no title, so [title] is read elsewhere.
/// [withComments] where [object] holds the whole conversation.
Issue issueRecord(
  JsonObject object, {
  required String title,
  bool withComments = false,
}) => Issue(
  id: requireInt(object, 'id'),
  type: switch (object['issueType']) {
    1 => IssueType.video,
    2 => IssueType.audio,
    3 => IssueType.subtitles,
    _ => IssueType.other,
  },
  status: switch (object['status']) {
    1 => IssueStatus.open,
    2 => IssueStatus.resolved,
    _ => IssueStatus.unknown,
  },
  mediaRef: issueRef(object),
  title: title,
  createdBy: serviceUser(object['createdBy']),
  createdAt: _requireTime(object, 'createdAt'),
  comments: [
    if (withComments)
      for (final comment in asObjects(object['comments']))
        IssueComment(
          id: requireInt(comment, 'id'),
          author: serviceUser(comment['user']),
          message: _requireString(comment, 'message'),
          createdAt: _requireTime(comment, 'createdAt'),
        ),
  ],
);
