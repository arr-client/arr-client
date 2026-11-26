import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../api/radarr_api.dart';
import '../models/json_fields.dart';
import '../models/movie_record.dart';
import 'queued_movies.dart';

/// A movie's release dates, in the order releases of one day are listed.
/// `releaseDate` is the server's pick among them, so it is not one more.
const _releaseFields = [
  ('inCinemas', CalendarDateKind.inCinemas),
  ('digitalRelease', CalendarDateKind.digitalRelease),
  ('physicalRelease', CalendarDateKind.physicalRelease),
];

/// The releases and imports of one Radarr instance.
///
/// A release carries the movie's state, so [events] reads the queue too and
/// fails if that read does. An import has no state.
final class RadarrCalendarAdapter implements CalendarProvider {
  /// Reads through [_api] for the instance [_instanceId].
  RadarrCalendarAdapter(this._api, this._instanceId);

  final RadarrApi _api;
  final String _instanceId;

  @override
  ServiceResult<List<CalendarEvent>> events(DateTime from, DateTime to) async =>
      switch (await queuedMovies(_api)) {
        Ok(:final value) => await _calendar(queued: value).events(from, to),
        Err(:final error) => Err(error),
      };

  @override
  ServiceResult<List<ImportedItem>> recentlyAdded() =>
      _calendar().recentlyAdded();

  @override
  ServiceResult<List<ImportedItem>> importedOn(DateTime day) =>
      _calendar().importedOn(day);

  /// The family's calendar, giving the movies of [queued] as downloading.
  ServarrCalendar _calendar({Set<int> queued = const {}}) => ServarrCalendar(
    _api.shared,
    calendarEvents: (record) => _releases(record, queued),
    calendarQuery: const {},
    importTitle: _importTitle,
    historyQuery: const {
      'includeMovie': ['true'],
    },
  );

  /// One event for each release date of the movie in [record].
  List<CalendarEvent> _releases(JsonObject record, Set<int> queued) {
    final id = requireInt(record, 'id');
    final ref = ItemRef(
      instanceId: _instanceId,
      kind: MediaKind.movie,
      remoteId: id,
    );
    final title = requireText(record, 'title');
    final state = movieState(record, downloading: queued.contains(id));
    return [
      for (final (field, kind) in _releaseFields)
        if (_day(record, field) case final date?)
          CalendarEvent(
            itemRef: ref,
            title: title,
            date: date,
            dateKind: kind,
            state: state,
          ),
    ];
  }
}

/// The day in [field], as local midnight.
///
/// Radarr writes a release day as midnight UTC. It is not an instant: converted
/// to the device's zone it would be the day before anywhere west of UTC.
DateTime? _day(JsonObject record, String field) {
  final written = DateTime.tryParse(optionalText(record, field) ?? '')?.toUtc();
  return written == null
      ? null
      : DateTime(written.year, written.month, written.day);
}

/// The movie's title, or the release's name where the server matched no movie.
String _importTitle(JsonObject record) => switch (record['movie']) {
  final JsonObject movie => requireText(movie, 'title'),
  _ => requireText(record, 'sourceTitle'),
};

/// The wanted lists of one Radarr instance, sorted by title.
///
/// As for the library, a list fails if the queue cannot be read. A page is not
/// the library, so nothing is cached.
final class RadarrWantedAdapter implements WantedProvider {
  /// Reads through [_api] for the instance [_instanceId].
  RadarrWantedAdapter(this._api, this._instanceId);

  final RadarrApi _api;
  final String _instanceId;

  @override
  ServiceResult<ResultPage<LibraryItem>> missing({int page = 1}) =>
      _withQueue((wanted) => wanted.missing(page: page));

  @override
  ServiceResult<ResultPage<LibraryItem>> cutoffUnmet({int page = 1}) =>
      _withQueue((wanted) => wanted.cutoffUnmet(page: page));

  /// Reads the queue, then a list of the family's wanted lists.
  ServiceResult<ResultPage<LibraryItem>> _withQueue(
    ServiceResult<ResultPage<LibraryItem>> Function(ServarrWanted wanted) list,
  ) async => switch (await queuedMovies(_api)) {
    Ok(:final value) => await list(_wanted(value)),
    Err(:final error) => Err(error),
  };

  /// The family's wanted lists, giving the movies of [queued] as downloading.
  ServarrWanted _wanted(Set<int> queued) => ServarrWanted(
    _api.shared,
    item: (record) => readMovie(
      record,
      instanceId: _instanceId,
      state: movieState(record, downloading: queued.contains(record['id'])),
    ),
    // Radarr's own order is by title, descending.
    query: const {
      'sortKey': ['movieMetadata.sortTitle'],
      'sortDirection': ['ascending'],
    },
  );
}
