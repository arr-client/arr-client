/// Readarr's library.
library;

import 'dart:convert';

import 'package:core/core.dart';

import '../api/readarr_api.dart';
import '../models/json_fields.dart';
import '../models/library_record.dart';
import '../models/media_record.dart';
import 'monitor_options.dart';

/// Authors and their books.
///
/// The state of an item depends on the download queue, so [list], [item] and
/// [children] read it too. If that read fails they fail and leave the cache as
/// it was: a queued book would otherwise be shown, and cached, as missing.
/// An item the server no longer has is removed from the cache.
///
/// Only [item] reads the editions of a book. The cache keeps them with the
/// book, also over a later [children], which does not read them.
final class ReadarrLibraryAdapter implements LibraryProvider {
  /// Reads with [_api] into [_cache].
  ReadarrLibraryAdapter(this._api, this._cache);

  final ReadarrApi _api;
  final CacheScope _cache;

  @override
  MediaKind get itemKind => MediaKind.author;

  @override
  List<MonitorOption> get monitorOptions => readarrMonitorOptions;

  @override
  ServiceResult<List<LibraryItem>> list() async {
    final List<JsonObject> records;
    switch (await _api.authors()) {
      case Ok(:final value):
        records = value;
      case Err(:final error):
        return Err(error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    final downloading = {for (final item in queue) ?item.parent?.remoteId};
    return _reading(() async {
      final now = DateTime.now().toUtc();
      final items = <LibraryItem>[];
      final entries = <CacheEntry>[];
      for (final record in records) {
        final (author, entry) = _author(
          record,
          downloading: downloading.contains(record['id']),
          now: now,
        );
        items.add(author);
        entries.add(entry);
      }
      await _cache.replace(MediaKind.author, entries);
      return items;
    });
  }

  @override
  ServiceResult<LibraryItem> item(ItemRef ref) => switch (ref.kind) {
    MediaKind.author => _oneAuthor(ref),
    MediaKind.book => _oneBook(ref),
    _ => throw _notOfThisRead(ref),
  };

  /// The books of an author.
  @override
  ServiceResult<List<LibraryItem>> children(ItemRef parent) {
    if (parent.kind != MediaKind.author) throw _notOfThisRead(parent);
    return _books(parent);
  }

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedList() => _reading(() async {
    final snapshot = await _cache.read(MediaKind.author);
    if (snapshot == null) return null;
    return Cached([
      for (final entry in snapshot.entries) _cachedAuthor(entry),
    ], fetchedAt: snapshot.fetchedAt);
  });

  @override
  ServiceResult<Cached<LibraryItem>?> cachedItem(ItemRef ref) {
    if (ref.kind != MediaKind.author && ref.kind != MediaKind.book) {
      throw _notOfThisRead(ref);
    }
    return _reading(() async {
      final entry = await _cache.entry(ref.kind, ref.remoteId);
      if (entry == null) return null;
      return Cached(
        entry.kind == MediaKind.author
            ? _cachedAuthor(entry)
            : await _cachedBook(entry),
        fetchedAt: entry.fetchedAt,
      );
    });
  }

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedChildren(ItemRef parent) {
    if (parent.kind != MediaKind.author) throw _notOfThisRead(parent);
    return _reading(() async {
      final snapshot = await _cache.read(
        MediaKind.book,
        parentRemoteId: parent.remoteId,
      );
      if (snapshot == null) return null;
      return Cached([
        for (final entry in snapshot.entries) await _cachedBook(entry),
      ], fetchedAt: snapshot.fetchedAt);
    });
  }

  @override
  ServiceResult<List<MediaFile>> files(ItemRef ref) {
    final read = switch (ref.kind) {
      MediaKind.author => _api.authorFiles,
      MediaKind.book => _api.bookFiles,
      _ => throw _notOfThisRead(ref),
    };
    return _files(ref, read(ref.remoteId));
  }

  @override
  ServiceResult<List<ServerOption>> options() async {
    final result = await _api.options();
    if (result case Ok(:final value)) await _cache.replaceOptions(value);
    return result;
  }

  @override
  ServiceResult<Cached<List<ServerOption>>?> cachedOptions() async =>
      Ok(await _cache.readOptions());

  /// Readarr provides no credits.
  @override
  ServiceResult<List<Credit>> credits(ItemRef ref) async => const Ok([]);

  @override
  ServiceResult<void> setMonitored(MediaTarget target, bool monitored) =>
      throw UnimplementedError('T120');

  @override
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId) =>
      throw UnimplementedError('T120');

  @override
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes) =>
      throw UnimplementedError('T120');

  @override
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes) =>
      throw UnimplementedError('T120');

  @override
  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  }) => throw UnimplementedError('T120');

  @override
  ServiceResult<void> deleteFile(MediaFile file) =>
      throw UnimplementedError('T120');

  @override
  ModuleRoute detailRoute(ItemRef ref) => throw UnimplementedError('T121');

  ServiceResult<List<MediaFile>> _files(
    ItemRef ref,
    ServiceResult<List<JsonObject>> answer,
  ) async => switch (await answer) {
    Ok(:final value) => _reading(() async => value.map(readFile).toList()),
    Err(:final error) => _gone(ref, error),
  };

  ServiceResult<LibraryItem> _oneAuthor(ItemRef ref) async {
    final JsonObject record;
    switch (await _api.author(ref.remoteId)) {
      case Ok(:final value):
        record = value;
      case Err(:final error):
        return _gone(ref, error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    return _reading(() async {
      final (author, entry) = _author(
        record,
        downloading: queue.any((item) => item.parent == ref),
        now: DateTime.now().toUtc(),
      );
      await _cache.put(entry);
      return author;
    });
  }

  ServiceResult<LibraryItem> _oneBook(ItemRef ref) async {
    final JsonObject record;
    switch (await _api.book(ref.remoteId)) {
      case Ok(:final value):
        record = value;
      case Err(:final error):
        return _gone(ref, error);
    }
    final List<JsonObject> editions;
    switch (_notGone(await _api.editions(ref.remoteId))) {
      case Ok(:final value):
        editions = value;
      case Err(:final error):
        return Err(error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    return _reading(() async {
      final (book, entry) = _book(
        {...record, 'editions': editions},
        authorName: embeddedAuthorName(record),
        downloading: queue.any((item) => item.itemRef == ref),
        now: DateTime.now().toUtc(),
      );
      await _cache.put(entry);
      return book;
    });
  }

  ServiceResult<List<LibraryItem>> _books(ItemRef parent) async {
    final id = parent.remoteId;
    final List<JsonObject> records;
    switch (await _api.books(id)) {
      case Ok(:final value):
        records = value;
      case Err(:final error):
        return _gone(parent, error);
    }
    // The books do not name their author.
    final JsonObject author;
    switch (await _api.author(id)) {
      case Ok(:final value):
        author = value;
      case Err(:final error):
        return _gone(parent, error);
    }
    final List<QueueItem> queue;
    switch (await _queue()) {
      case Ok(:final value):
        queue = value;
      case Err(:final error):
        return Err(error);
    }
    final downloading = {for (final item in queue) ?item.itemRef?.remoteId};
    return _reading(() async {
      final now = DateTime.now().toUtc();
      final (read, authorEntry) = _author(
        author,
        downloading: queue.any((item) => item.parent == parent),
        now: now,
      );
      final items = <LibraryItem>[];
      final entries = <CacheEntry>[];
      for (final record in records) {
        final bookId = requireInt(record, 'id');
        final (book, entry) = _book(
          // Editions read before stay with the book.
          {...record, 'editions': ?await _cachedEditions(bookId)},
          authorName: read.title,
          downloading: downloading.contains(bookId),
          now: now,
        );
        items.add(book);
        entries.add(entry);
      }
      await _cache.put(authorEntry);
      await _cache.replace(MediaKind.book, entries, parentRemoteId: id);
      return items;
    });
  }

  /// A read beside that of an item: its NotFound would say that the item is
  /// gone.
  Result<T, ServiceFailure> _notGone<T>(Result<T, ServiceFailure> result) =>
      switch (result) {
        Err(error: NotFound()) => const Err(ServerError(statusCode: 404)),
        _ => result,
      };

  /// The queue, for the states of items.
  ServiceResult<List<QueueItem>> _queue() async => _notGone(await _api.queue());

  /// The editions the cache has of the book [id], if it has any.
  Future<Object?> _cachedEditions(int id) async {
    final entry = await _cache.entry(MediaKind.book, id);
    return entry == null ? null : _decode(entry)['editions'];
  }

  /// An author and what the cache keeps of it.
  (Author, CacheEntry) _author(
    JsonObject record, {
    required bool downloading,
    required DateTime now,
  }) {
    final author = readAuthor(
      record,
      _api.authorRef(requireInt(record, 'id')),
      authorState(record, downloading: downloading),
    );
    return (author, _entry(author, record, now: now));
  }

  /// A book and what the cache keeps of it.
  (Book, CacheEntry) _book(
    JsonObject record, {
    required String? authorName,
    required bool downloading,
    required DateTime now,
  }) {
    final book = readBook(
      record,
      ref: _api.bookRef(requireInt(record, 'id')),
      author: _api.authorRef(requireInt(record, 'authorId')),
      authorName: authorName,
      state: bookState(record, downloading: downloading, now: now),
    );
    return (book, _entry(book, record, now: now));
  }

  CacheEntry _entry(
    LibraryItem item,
    JsonObject record, {
    required DateTime now,
  }) => CacheEntry(
    instanceId: item.ref.instanceId,
    kind: item.ref.kind,
    remoteId: item.ref.remoteId,
    parentRemoteId: item.parent?.remoteId,
    sortTitle: item.sortTitle,
    state: item.state,
    monitored: item.monitored,
    qualityProfileId: item.qualityProfileId,
    tagIds: item.tagIds.toList(),
    addedAt: item.addedAt,
    rawJson: jsonEncode(record),
    fetchedAt: now,
  );

  // The state is the one found when fetched: the queue is not cached.
  Author _cachedAuthor(CacheEntry entry) =>
      readAuthor(_decode(entry), _api.authorRef(entry.remoteId), entry.state);

  Future<Book> _cachedBook(CacheEntry entry) async {
    final record = _decode(entry);
    final authorId = entry.parentRemoteId ?? requireInt(record, 'authorId');
    var authorName = embeddedAuthorName(record);
    if (authorName == null) {
      // A book of a list does not name its author, who is cached beside it.
      final author = await _cache.entry(MediaKind.author, authorId);
      if (author != null) {
        authorName = optionalText(_decode(author), 'authorName');
      }
    }
    return readBook(
      record,
      ref: _api.bookRef(entry.remoteId),
      author: _api.authorRef(authorId),
      authorName: authorName,
      state: entry.state,
    );
  }

  JsonObject _decode(CacheEntry entry) => asObject(jsonDecode(entry.rawJson));

  /// A failed read of [ref], which leaves the cache if it no longer exists.
  Future<Result<T, ServiceFailure>> _gone<T>(
    ItemRef ref,
    ServiceFailure failure,
  ) async {
    if (failure is NotFound) await _cache.remove(ref.kind, ref.remoteId);
    return Err(failure);
  }
}

ArgumentError _notOfThisRead(ItemRef ref) =>
    ArgumentError.value(ref.kind, 'kind', 'not an item of this read');

/// What [read] makes of records, which may be of a shape it cannot understand.
Future<Result<T, ServiceFailure>> _reading<T>(Future<T> Function() read) async {
  try {
    return Ok(await read());
  } on FormatException {
    // The exception may quote a record, so it goes no further.
    return const Err(MalformedResponse());
  }
}
