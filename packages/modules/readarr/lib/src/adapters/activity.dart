/// Readarr's queue, history, blocklist and manual import. All of it is the
/// shared Servarr client's but the history of one item and how a file is
/// matched to an author, a book and an edition of it.
library;

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../api/readarr_api.dart';
import '../models/json_fields.dart';

/// The download queue and manual import.
final class ReadarrQueueAdapter implements QueueProvider {
  /// Reads and writes with [_api].
  ReadarrQueueAdapter(this._api);

  final ReadarrApi _api;

  @override
  ServiceResult<List<QueueItem>> queue() => _api.queue();

  @override
  ServiceResult<void> remove(int queueId, RemoveOptions options) =>
      _api.shared.remove(queueId, options);

  @override
  ServiceResult<void> removeMany(List<int> queueIds, RemoveOptions options) =>
      _api.shared.removeMany(queueIds, options);

  @override
  ServiceResult<void> grabNow(int queueId) => _api.shared.grabNow(queueId);

  @override
  ServiceResult<List<ManualImportCandidate>> importCandidates(QueueItem item) =>
      _api.shared.importCandidates(item, mapping: _mapping);

  @override
  ServiceResult<ImportChoices> importChoices() => _api.shared.importChoices();

  /// A candidate without an author is [Validation], and then nothing is
  /// written. The server chooses the edition, and may choose another book than
  /// the one sent.
  @override
  ServiceResult<List<ManualImportCandidate>> reprocess(
    List<ManualImportCandidate> candidates,
  ) async {
    if (!candidates.every((candidate) => candidate.matchedRef != null)) {
      return const Err(Validation([]));
    }
    final sent = {
      for (final candidate in candidates) candidate.path: candidate,
    };
    return switch (await _api.shared.reprocess(candidates, mapping: _mapping)) {
      Ok(:final value) => Ok([
        for (final answer in value) _ofItsBook(answer, sent[answer.path]),
      ]),
      Err(:final error) => Err(error),
    };
  }

  /// A candidate without an author, a book and an edition of that book is
  /// [Validation], and then nothing is written. Only the server chooses an
  /// edition, so a newly chosen book takes a [reprocess] first.
  ///
  /// Importing deletes files. Before it puts the new file there, Readarr
  /// deletes every file the book already has, of whatever format or edition:
  /// for good where the server has no recycle bin, and in a Calibre library by
  /// removing the book's formats from Calibre. `replaceExistingFiles`, which is
  /// never sent, does not change this. It also makes the file's edition the one
  /// the book is monitored for, and of several files of one book with the same
  /// part number, as any two e-books are, imports only one. A screen that
  /// imports with this must warn of the deletion before it does.
  @override
  ServiceResult<Command> importFiles(
    List<ManualImportCandidate> candidates,
  ) async {
    if (!candidates.every(_isComplete)) return const Err(Validation([]));
    return _api.shared.importFiles(candidates, mapping: _mapping);
  }

  bool _isComplete(ManualImportCandidate candidate) =>
      candidate.matchedRef != null &&
      candidate.bookId != null &&
      _editionId(candidate) != null;

  /// The edition the server gave for the author and book now chosen. One it
  /// gave for another book is not one of this book.
  String? _editionId(ManualImportCandidate candidate) {
    final record = candidate.rawJson;
    final isOfMatch =
        objectIn(record, 'book')['id'] == candidate.bookId &&
        objectIn(record, 'author')['id'] == candidate.matchedRef?.remoteId;
    return isOfMatch ? optionalText(record, 'foreignEditionId') : null;
  }

  /// [answer] without the edition of the book [sent] had before, where the
  /// server now names another book and no edition: the record keeps what the
  /// answer leaves out.
  ManualImportCandidate _ofItsBook(
    ManualImportCandidate answer,
    ManualImportCandidate? sent,
  ) {
    final before = sent?.rawJson;
    if (before == null ||
        objectIn(before, 'book')['id'] == answer.bookId ||
        answer.rawJson['foreignEditionId'] != before['foreignEditionId']) {
      return answer;
    }
    return ManualImportCandidate(
      path: answer.path,
      size: answer.size,
      downloadId: answer.downloadId,
      selected: answer.selected,
      matchedRef: answer.matchedRef,
      bookId: answer.bookId,
      quality: answer.quality,
      languages: answer.languages,
      rejections: answer.rejections,
      rawJson: {...answer.rawJson}..remove('foreignEditionId'),
    );
  }

  ServarrImportMapping get _mapping => (match: _match, ids: _ids);

  ServarrMatch _match(JsonObject record) {
    final authorId = optionalPositive(objectIn(record, 'author'), 'id');
    return (
      item: authorId == null ? null : _api.authorRef(authorId),
      episodeIds: const [],
    );
  }

  JsonObject _ids(ManualImportCandidate candidate) => {
    'authorId': ?candidate.matchedRef?.remoteId,
    'bookId': ?candidate.bookId,
    'foreignEditionId': ?_editionId(candidate),
  };
}

/// The history, overall or of an author or a book, and the blocklist.
final class ReadarrHistoryAdapter implements HistoryProvider {
  /// Reads and writes with [_api].
  ReadarrHistoryAdapter(this._api);

  final ReadarrApi _api;

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) async {
    if (target == null) return _api.shared.history(page: page);
    final ref = target.item;
    if (ref.instanceId == _api.instanceId && target.seasonNumber == null) {
      switch (ref.kind) {
        case MediaKind.book:
          return _api.bookHistory(ref.remoteId, page: page);
        case MediaKind.author:
          // Readarr gives the history of an author whole, as the first page.
          if (page != 1) {
            return Ok(ResultPage(items: const [], page: page, hasMore: false));
          }
          return switch (await _api.authorHistory(ref.remoteId)) {
            Ok(:final value) => Ok(
              ResultPage(items: value, page: page, hasMore: false),
            ),
            Err(:final error) => Err(error),
          };
        default:
      }
    }
    throw ArgumentError.value(ref.kind, 'kind', 'not an item of this read');
  }

  @override
  ServiceResult<void> markFailed(int eventId) =>
      _api.shared.markFailed(eventId);

  @override
  ServiceResult<List<HistoryEvent>> eventsSince(DateTime since) =>
      _api.shared.eventsSince(since);

  @override
  ServiceResult<ResultPage<BlocklistEntry>> blocklist({int page = 1}) =>
      _api.shared.blocklist(page: page);

  @override
  ServiceResult<void> unblock(List<int> entryIds) =>
      _api.shared.unblock(entryIds);
}
