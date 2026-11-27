/// Readarr's calendar, imports and wanted lists, all of books. Health and disk
/// space are the shared Servarr ones as they are.
///
/// The state of a book depends on the download queue, so
/// [ReadarrCalendarAdapter.events] and the wanted lists read it too, and fail
/// if that read fails: a queued book would otherwise be shown as missing. An
/// import has no state, so the two reads of imports leave the queue alone.
library;

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../api/readarr_api.dart';
import '../models/json_fields.dart';
import '../models/library_record.dart';

const _includeAuthor = {
  'includeAuthor': ['true'],
};

/// Upcoming books and the books imported.
final class ReadarrCalendarAdapter implements CalendarProvider {
  /// Reads with [_api].
  ReadarrCalendarAdapter(this._api);

  final ReadarrApi _api;

  /// The monitored books released in the window.
  @override
  ServiceResult<List<CalendarEvent>> events(
    DateTime from,
    DateTime to,
  ) async => switch (await _queued(_api)) {
    // Before the calendar, so that a download that ends between the two reads
    // does not leave its book missing.
    Ok(:final value) => _calendar(downloading: value).events(from, to),
    Err(:final error) => Err(error),
  };

  /// Readarr records an import for each file; each book is listed once.
  @override
  ServiceResult<List<ImportedItem>> recentlyAdded() =>
      _calendar().recentlyAdded();

  @override
  ServiceResult<List<ImportedItem>> importedOn(DateTime day) =>
      _calendar().importedOn(day);

  /// The shared calendar. Only its events use [downloading].
  ServarrCalendar _calendar({Set<int> downloading = const {}}) =>
      ServarrCalendar(
        _api.shared,
        calendarEvents: (record) => _events(record, downloading: downloading),
        calendarQuery: _includeAuthor,
        importTitle: _importTitle,
        historyQuery: const {
          ..._includeAuthor,
          'includeBook': ['true'],
        },
        importEvent: 'bookFileImported',
      );

  /// A record of `GET calendar`. A book without a release date is left out.
  List<CalendarEvent> _events(
    JsonObject record, {
    required Set<int> downloading,
  }) {
    final id = requireInt(record, 'id');
    final released = optionalTime(record, 'releaseDate');
    if (released == null) return const [];
    return [
      CalendarEvent(
        itemRef: _api.bookRef(id),
        title: _title(embeddedAuthorName(record), requireText(record, 'title')),
        date: released,
        dateKind: CalendarDateKind.releaseDate,
        state: bookState(
          record,
          downloading: downloading.contains(id),
          now: DateTime.now().toUtc(),
        ),
      ),
    ];
  }
}

/// Monitored books without a file, and below their cutoff, latest released
/// first. A page is not the library, so nothing is cached.
final class ReadarrWantedAdapter implements WantedProvider {
  /// Reads with [_api].
  ReadarrWantedAdapter(this._api);

  final ReadarrApi _api;

  @override
  ServiceResult<ResultPage<LibraryItem>> missing({int page = 1}) =>
      _read((wanted) => wanted.missing(page: page));

  @override
  ServiceResult<ResultPage<LibraryItem>> cutoffUnmet({int page = 1}) =>
      _read((wanted) => wanted.cutoffUnmet(page: page));

  ServiceResult<ResultPage<LibraryItem>> _read(
    ServiceResult<ResultPage<LibraryItem>> Function(ServarrWanted wanted) list,
  ) async => switch (await _queued(_api)) {
    Err(:final error) => Err(error),
    Ok(value: final downloading) => await list(
      ServarrWanted(
        _api.shared,
        item: (record) => _book(record, downloading: downloading),
        // Stated: the cutoff list has no order of its own.
        query: const {
          ..._includeAuthor,
          'sortKey': ['releaseDate'],
          'sortDirection': ['descending'],
        },
      ),
    ),
  };

  /// A record of `GET wanted/missing` or `GET wanted/cutoff`.
  Book _book(JsonObject record, {required Set<int> downloading}) {
    final id = requireInt(record, 'id');
    return readBook(
      record,
      ref: _api.bookRef(id),
      author: _api.authorRef(requireInt(record, 'authorId')),
      authorName: embeddedAuthorName(record),
      state: bookState(
        record,
        downloading: downloading.contains(id),
        now: DateTime.now().toUtc(),
      ),
    );
  }
}

/// The ids of the books in the download queue.
Future<Result<Set<int>, ServiceFailure>> _queued(ReadarrApi api) async =>
    switch (await api.queue()) {
      Ok(:final value) => Ok({
        for (final item in value) ?item.itemRef?.remoteId,
      }),
      // NotFound would say that what was asked for is gone.
      Err(error: NotFound()) => const Err(ServerError(statusCode: 404)),
      Err(:final error) => Err(error),
    };

/// The title of a history record: of its book, or the release's name if the
/// record does not name one.
String _importTitle(JsonObject record) {
  final book = optionalText(objectIn(record, 'book'), 'title');
  if (book == null) return optionalText(record, 'sourceTitle') ?? '';
  return _title(optionalText(objectIn(record, 'author'), 'authorName'), book);
}

/// What names a book among those of other authors.
String _title(String? author, String book) => [?author, book].join(' - ');
