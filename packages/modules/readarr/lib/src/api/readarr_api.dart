import 'dart:convert';

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../models/json_fields.dart';

const _apiPath = 'api/v1';

/// Readarr's requests for one instance.
///
/// As in [ServarrClient], a failure of the HTTP client is returned unchanged,
/// nothing is retried, and an answer of another shape is [MalformedResponse].
final class ReadarrApi {
  /// The API of the instance of [context].
  ReadarrApi(InstanceContext context)
    : instanceId = context.instance.id,
      _http = context.http,
      shared = ServarrClient(
        context.http,
        apiPath: _apiPath,
        includeUnknownParameter: 'includeUnknownAuthorItems',
        refs: (record) => _refs(context.instance.id, record),
        hasMetadataProfiles: true,
        correctsLanguages: false,
      );

  /// The instance whose items the records are.
  final String instanceId;

  /// The client for what the family shares as it is.
  final ServarrClient shared;

  final ServiceHttpClient _http;

  /// The key of the author [id].
  ItemRef authorRef(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.author, remoteId: id);

  /// The key of the book [id].
  ItemRef bookRef(int id) =>
      ItemRef(instanceId: instanceId, kind: MediaKind.book, remoteId: id);

  /// Every author, as received.
  ServiceResult<List<JsonObject>> authors() => shared.read('author', asObjects);

  /// One author, as received.
  ServiceResult<JsonObject> author(int id) =>
      shared.read('author/$id', asObject);

  /// The books of an author, which name neither their author nor editions. An
  /// author the server does not have is [NotFound].
  ServiceResult<List<JsonObject>> books(int authorId) =>
      shared.read('book', asObjects, query: _ofAuthor(authorId));

  /// One book, with its author but without its editions.
  ServiceResult<JsonObject> book(int id) => shared.read('book/$id', asObject);

  /// The editions of a book. A book the server does not have gets an empty
  /// list.
  ServiceResult<List<JsonObject>> editions(int bookId) =>
      shared.read('edition', asObjects, query: _ofBook(bookId));

  /// The book files of an author.
  ServiceResult<List<JsonObject>> authorFiles(int authorId) =>
      shared.read('bookfile', asObjects, query: _ofAuthor(authorId));

  /// The files of a book.
  ServiceResult<List<JsonObject>> bookFiles(int bookId) =>
      shared.read('bookfile', asObjects, query: _ofBook(bookId));

  /// The authors and books the server's metadata source finds for [term],
  /// which may be `author:<id>` or `work:<id>` with an id of that source. Each
  /// result holds an `author` or a `book`; one the server has carries its id.
  ///
  /// Unlike `book/lookup` it gives a book its author and editions, which adding
  /// the book takes.
  ServiceResult<List<JsonObject>> search(String term) => shared.read(
    'search',
    asObjects,
    query: {
      'term': [term],
    },
  );

  /// The root folders, as received.
  ServiceResult<List<JsonObject>> rootFolders() =>
      shared.read('rootfolder', asObjects);

  /// Adds [author], sending it once, and gives its id. If the server accepts it
  /// without saying which author it made, that is [OutcomeUnknown].
  ServiceResult<int> addAuthor(JsonObject author) => _add('author', author);

  /// As [addAuthor], for a book with its author.
  ServiceResult<int> addBook(JsonObject book) => _add('book', book);

  /// The whole download queue.
  ServiceResult<List<QueueItem>> queue() => shared.queue();

  /// Quality and metadata profiles, root folders and tags.
  ServiceResult<List<ServerOption>> options() => shared.options();

  // The server refuses an author it has by a validator, but a book only by its
  // database, which the HTTP client reports as [Conflict] itself.
  ServiceResult<int> _add(String path, JsonObject record) async {
    final request = ServiceRequest(
      HttpMethod.post,
      '$_apiPath/$path',
      body: JsonBody(record),
    );
    switch (await _http.send(request)) {
      case Err(:final error):
        return Err(
          _refusedAsExisting(error) ? const Conflict() : error.failure,
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

  static Map<String, List<String>> _ofAuthor(int id) => {
    'authorId': ['$id'],
  };

  static Map<String, List<String>> _ofBook(int id) => {
    'bookId': ['$id'],
  };
}

/// Whether a refused add says that the author is there already. Other
/// refusals, a folder already in use included, stay as they are.
bool _refusedAsExisting(HttpError error) {
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
        (refusal) =>
            refusal is JsonObject &&
            refusal['errorCode'] == 'AuthorExistsValidator',
      );
}

/// A queue or history record is about a book of an author. A blocklist record
/// lists its books: one of several is not what it is about.
ServarrRefs _refs(String instanceId, JsonObject record) {
  ItemRef? ref(MediaKind kind, Object? value) => switch (value) {
    final int id when id > 0 => ItemRef(
      instanceId: instanceId,
      kind: kind,
      remoteId: id,
    ),
    _ => null,
  };
  final bookId = switch (record['bookIds']) {
    [final only] => only,
    _ => record['bookId'],
  };
  return (
    item: ref(MediaKind.book, bookId),
    parent: ref(MediaKind.author, record['authorId']),
  );
}
