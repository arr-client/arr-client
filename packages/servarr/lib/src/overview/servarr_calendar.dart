import 'package:core/core.dart';

import '../json_reading.dart';
import '../records/import_record.dart';
import '../servarr_client.dart';

/// The calendar and the imports of a service of the Servarr family.
///
/// [recentlyAdded] and [importedOn] list imports from a download folder, newest
/// first and each item once with its latest import.
final class ServarrCalendar implements CalendarProvider {
  /// The calendar of one service.
  ///
  /// [calendarEvents] reads the dated releases of one `calendar` record and
  /// [importTitle] the title to show for one history record; both throw
  /// [FormatException] for a record they cannot understand. [calendarQuery]
  /// and [historyQuery] are the service's own parameters, such as those that
  /// make its records name their item.
  ///
  /// [startOfDay] gives the first instant of a day, and takes days past the
  /// end of a month as [DateTime] does. It is the device's local midnight unless
  /// a test puts another time zone in its place.
  ServarrCalendar(
    this._client, {
    required this._calendarEvents,
    required this._calendarQuery,
    required this._importTitle,
    required this._historyQuery,
    this._startOfDay = _localMidnight,
  });

  static const _recentPageSize = 50;

  /// More than any time zone is away from UTC. A movie's dates are days written
  /// as midnight UTC, which may be placed anywhere in that day of the device's
  /// zone.
  static const _calendarMargin = Duration(days: 1);

  /// `history/since` compares its `date` as text with stored times that have
  /// fractions of a second, and may leave out an event of that same second.
  static const _sinceMargin = Duration(seconds: 1);

  final ServarrClient _client;
  final List<CalendarEvent> Function(JsonObject record) _calendarEvents;
  final Map<String, List<String>> _calendarQuery;
  final String Function(JsonObject record) _importTitle;
  final Map<String, List<String>> _historyQuery;
  final DateTime Function(int year, int month, int day) _startOfDay;

  static DateTime _localMidnight(int year, int month, int day) =>
      DateTime(year, month, day);

  /// The releases dated from [from] up to, but not including, [to], oldest
  /// first, by the dates the module's mapper gives. Releases of the same date
  /// keep the server's order.
  @override
  ServiceResult<List<CalendarEvent>> events(DateTime from, DateTime to) =>
      _client.read(
        'calendar',
        (json) {
          // A record is in the answer when any one of its dates is in the
          // range, so each date is held against the window.
          final events = [
            for (final record in asObjects(json))
              for (final event in _calendarEvents(record))
                if (!event.date.isBefore(from) && event.date.isBefore(to))
                  event,
          ];
          // Releases of one moment, such as a whole season, keep the server's
          // order. `List.sort` alone would not: it is not stable.
          final ordered = events.indexed.toList()
            ..sort((a, b) {
              final byDate = a.$2.date.compareTo(b.$2.date);
              return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
            });
          return [for (final (_, event) in ordered) event];
        },
        query: {
          ..._calendarQuery,
          'start': [_wireDate(from.subtract(_calendarMargin))],
          'end': [_wireDate(to.add(_calendarMargin))],
        },
      );

  /// The items of the latest imports: one page of the history, so an older
  /// import is not listed.
  @override
  ServiceResult<List<ImportedItem>> recentlyAdded() => _client.read(
    'history',
    (json) => _imports(readPage(json, (record) => record).records),
    query: {
      ..._historyQuery,
      'page': ['1'],
      'pageSize': ['$_recentPageSize'],
      'sortKey': ['date'],
      'sortDirection': ['descending'],
      'eventType': [importEventNumber],
    },
  );

  /// What was imported on the year, month and day of [day] in the device's time
  /// zone, from its midnight up to the next one. The time of [day] is ignored.
  @override
  ServiceResult<List<ImportedItem>> importedOn(DateTime day) {
    final start = _startOfDay(day.year, day.month, day.day);
    // Not 24 hours on: a day on which the clocks change is shorter or longer.
    final end = _startOfDay(day.year, day.month, day.day + 1);
    return _client.read(
      'history/since',
      // The answer runs up to now, so later days are dropped here too.
      (json) => _imports(
        asObjects(json),
        within: (importedAt) =>
            !importedAt.isBefore(start) && importedAt.isBefore(end),
      ),
      query: {
        ..._historyQuery,
        'date': [_wireDate(start.subtract(_sinceMargin))],
        'eventType': [importEventNumber],
      },
    );
  }

  List<ImportedItem> _imports(
    List<JsonObject> records, {
    bool Function(DateTime importedAt)? within,
  }) => importedItems(
    records,
    itemRef: (record) => _client.refs(record).item,
    title: _importTitle,
    within: within,
  );

  /// In UTC, with `Z`: Radarr reads a date with an offset wrongly.
  static String _wireDate(DateTime instant) =>
      instant.toUtc().toIso8601String();
}
