/// Searching for authors and books and adding them.
library;

import 'package:core/core.dart';

import '../api/readarr_api.dart';
import '../models/json_fields.dart';
import '../models/library_record.dart';
import '../models/media_record.dart';
import 'monitor_options.dart';

/// New authors and books.
final class ReadarrLookupAdapter implements LookupProvider {
  /// Searches and adds with [_api].
  ReadarrLookupAdapter(this._api);

  final ReadarrApi _api;

  @override
  Set<MediaKind> get itemKinds => const {MediaKind.author, MediaKind.book};

  /// The authors and books found, in the server's order.
  @override
  ServiceResult<List<AddCandidate>> lookup(String term) async {
    // There is nothing to search for.
    if (term.trim().isEmpty) return const Ok([]);
    switch (await _api.search(term)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        try {
          return Ok([
            for (final result in value)
              for (final kind in itemKinds)
                if (result[_resultField(kind)] case final JsonObject record)
                  _candidate(kind, record),
          ]);
        } on FormatException {
          // The exception may quote a record, so it goes no further.
          return const Err(MalformedResponse());
        }
    }
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
  /// the id of the metadata source, with the choices set in it.
  ///
  /// A book brings its editions and its author along. An author the instance
  /// does not have is made with the choices; one it has is sent as found, and
  /// of the choices only `searchNow` then applies.
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
      AddOptions(serverOptions: value, monitorOptions: readarrMonitorOptions),
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
    return candidate.kind == MediaKind.author
        ? _addAuthor(record, choices)
        : _addBook(record, choices);
  }

  ServiceResult<ItemRef> _addAuthor(
    JsonObject record,
    AddChoices choices,
  ) async {
    final JsonObject author;
    switch (await _newAuthor(record, choices, search: choices.searchNow)) {
      case Ok(:final value):
        author = value;
      case Err(:final error):
        return Err(error);
    }
    return switch (await _api.addAuthor(author)) {
      Ok(:final value) => Ok(_api.authorRef(value)),
      Err(:final error) => Err(error),
    };
  }

  ServiceResult<ItemRef> _addBook(JsonObject record, AddChoices choices) async {
    var author = objectIn(record, 'author');
    if (author.isEmpty) return const Err(MalformedResponse());
    if (optionalPositive(author, 'id') == null) {
      // No search for the author: the server would search for all of it, where
      // only this book was asked for.
      switch (await _newAuthor(author, choices, search: false)) {
        case Ok(:final value):
          author = value;
        case Err(:final error):
          return Err(error);
      }
    }
    // A copy: the candidate may be added to another instance too.
    final book = <String, Object?>{
      ...record,
      'author': author,
      'monitored': true,
      'addOptions': <String, Object?>{'searchForNewBook': choices.searchNow},
    };
    return switch (await _api.addBook(book)) {
      Ok(:final value) => Ok(_api.bookRef(value)),
      Err(:final error) => Err(error),
    };
  }

  /// A copy of [record], an author the server does not have, as it is posted.
  ServiceResult<JsonObject> _newAuthor(
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
      // As Readarr's form does; the option decides which books are monitored.
      'monitored': true,
      'addOptions': <String, Object?>{
        'monitor': choices.monitorOptionId,
        'searchForMissingBooks': search,
      },
    });
  }

  /// The search result of this instance for [candidate].
  ServiceResult<JsonObject> _record(AddCandidate candidate) async {
    final own = candidate.sourceByInstance[_api.instanceId];
    if (own != null) return Ok(own);
    return _lookupAgain(candidate);
  }

  /// What the instance gives now for the metadata source's id of [candidate].
  ServiceResult<JsonObject> _lookupAgain(AddCandidate candidate) async {
    final id = candidate.externalIds.foreignId;
    if (id == null) return const Err(NotFound());
    final kind = candidate.kind;
    // A book is asked for by its work.
    final prefix = kind == MediaKind.author ? 'author' : 'work';
    switch (await _api.search('$prefix:$id')) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        for (final result in value) {
          if (result[_resultField(kind)] case final JsonObject record
              when record[_foreignIdField(kind)] == id) {
            return Ok(record);
          }
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

  /// The author or book of a result of `GET search`.
  AddCandidate _candidate(MediaKind kind, JsonObject record) {
    final isAuthor = kind == MediaKind.author;
    final id = optionalPositive(record, 'id');
    return AddCandidate(
      kind: kind,
      title: requireText(record, isAuthor ? 'authorName' : 'title'),
      parentTitle: isAuthor ? null : embeddedAuthorName(record),
      externalIds: ExternalIds(
        foreignId: optionalText(record, _foreignIdField(kind)),
      ),
      year: isAuthor ? null : optionalTime(record, 'releaseDate')?.year,
      overview: optionalText(record, 'overview'),
      images: readImages(record['images']),
      existingRefs: [
        if (id != null) isAuthor ? _api.authorRef(id) : _api.bookRef(id),
      ],
      sourceByInstance: {_api.instanceId: record},
    );
  }
}

// Where a search result holds an item of [kind].
String _resultField(MediaKind kind) =>
    kind == MediaKind.author ? 'author' : 'book';

// The id of the metadata source.
String _foreignIdField(MediaKind kind) =>
    kind == MediaKind.author ? 'foreignAuthorId' : 'foreignBookId';

void _requireAddable(MediaKind kind) {
  if (kind != MediaKind.author && kind != MediaKind.book) {
    throw ArgumentError.value(kind, 'kind', 'Readarr adds authors and books');
  }
}
