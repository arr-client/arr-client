// What the overview tests share, on top of support.dart.
//
// Fixtures (`overview_*.json`): recorded on 2026-11-26 from a throwaway Radarr
// 7.0.3.10918 and Sonarr 4.0.20.3014 in the dev stack's images, run with
// TZ=Pacific/Auckland, and passed through tool/sanitize_fixture.dart. A few
// public titles were added and small made-up files imported by hand, one of them
// upgraded. The free and total bytes of diskspace were then replaced by made-up
// numbers, as the recorded ones were those of the recording machine. What a
// test needs beyond the recordings it changes.
//
// Seen on those servers, and why the tests ask what they ask:
// - `history/since` compares its `date` as text with stored times that have
//   fractions of a second, while it answers with whole seconds: an event in the
//   same second as a `date` without a fraction is left out. So the app asks from
//   before the time it wants and drops what is too early itself.
// - Radarr reads a `date` with an offset wrongly; with `Z` both services agree.
// - Paged `history` takes `eventType` as a number only: 3 is the import from a
//   download folder on both.
// - `calendar` answers with a movie when any of its three dates is in the range,
//   and its movie dates are days written as midnight UTC.
//
// The mappers below stand in for those of the modules, which have their own
// tests; they read no more than these tests need.

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:servarr/servarr.dart';

import 'support.dart';

const _any = ParamRule.any();
const _nonEmpty = ParamRule.nonEmpty();
const _flag = ParamRule.only({'true', 'false'}, required: false);
const _paging = {
  'page': _any,
  'pageSize': _any,
  'sortKey': _any,
  'sortDirection': _any,
};

/// The requests of the overview reads. `servarr` may not import a module, so
/// this repeats, no wider, entries of the Radarr and Sonarr allow-lists.
AllowList _allowList(Service service) {
  final includes = {for (final name in service.historyQuery.keys) name: _flag};
  final series = {if (service == sonarr) 'includeSeries': _flag};
  return AllowList([
    AllowedRequest.read('api/v3/health'),
    AllowedRequest.read('api/v3/diskspace'),
    AllowedRequest.read(
      'api/v3/calendar',
      query: {
        'start': _any,
        'end': _any,
        'unmonitored': _flag,
        'tags': _any,
        ...series,
      },
    ),
    AllowedRequest.read(
      'api/v3/history',
      query: {..._paging, 'eventType': _any, ...includes},
    ),
    AllowedRequest.read(
      'api/v3/history/since',
      query: {'date': _nonEmpty, 'eventType': _any, ...includes},
    ),
    for (final path in ['wanted/missing', 'wanted/cutoff'])
      AllowedRequest.read(
        'api/v3/$path',
        query: {..._paging, 'monitored': _flag, ...series},
      ),
  ]);
}

extension OverviewService on Service {
  /// What the module asks for so that history records name their item.
  Map<String, List<String>> get historyQuery => this == radarr
      ? const {
          'includeMovie': ['true'],
        }
      : const {
          'includeSeries': ['true'],
          'includeEpisode': ['true'],
        };

  /// The same for calendar and wanted records.
  Map<String, List<String>> get itemQuery => this == radarr
      ? const {}
      : const {
          'includeSeries': ['true'],
        };

  ServarrClient overviewClient(FakeServer server) => ServarrClient(
    AllowListClient(_allowList(this), server),
    apiPath: 'api/v3',
    includeUnknownParameter: includeUnknown,
    refs: refs,
  );

  /// [startOfDay] stands for the device's time zone; null keeps the default.
  ServarrCalendar calendar(
    FakeServer server, {
    List<CalendarEvent> Function(JsonObject record)? events,
    DateTime Function(int year, int month, int day)? startOfDay,
  }) {
    final client = overviewClient(server);
    final calendarEvents =
        events ?? (this == radarr ? _movieEvents : _episodeEvents);
    return startOfDay == null
        ? ServarrCalendar(
            client,
            calendarEvents: calendarEvents,
            calendarQuery: itemQuery,
            importTitle: importTitle,
            historyQuery: historyQuery,
          )
        : ServarrCalendar(
            client,
            calendarEvents: calendarEvents,
            calendarQuery: itemQuery,
            importTitle: importTitle,
            historyQuery: historyQuery,
            startOfDay: startOfDay,
          );
  }

  ServarrWanted wanted(FakeServer server) => ServarrWanted(
    overviewClient(server),
    item: this == radarr ? _movie : _episode,
    query: itemQuery,
  );

  /// The title of an imported item.
  String importTitle(JsonObject record) => this == radarr
      ? _field(record, 'movie', 'title')
      : '${_field(record, 'series', 'title')} - '
            '${_field(record, 'episode', 'title')}';

  /// What an import record is about.
  ItemRef itemOf(int remoteId) => ItemRef(
    instanceId: instanceId,
    kind: this == radarr ? MediaKind.movie : MediaKind.episode,
    remoteId: remoteId,
  );

  /// The recorded import record [id] of `history/since`, to change and serve.
  JsonObject import(int id, {required DateTime date, int? item, int? newId}) {
    final record = list('overview_history_since')
        .singleWhere((record) => record['id'] == id);
    record['date'] = date.toUtc().toIso8601String();
    if (newId != null) record['id'] = newId;
    if (item != null) {
      record[this == radarr ? 'movieId' : 'episodeId'] = item;
    }
    return record;
  }
}

String _field(JsonObject record, String object, String field) =>
    switch (record[object]) {
      final JsonObject value => value[field]! as String,
      _ => record['sourceTitle']! as String,
    };

ItemState _state(JsonObject record) =>
    record['hasFile'] == true ? ItemState.downloaded : ItemState.missing;

List<CalendarEvent> _movieEvents(JsonObject record) => [
  for (final (field, kind) in const [
    ('inCinemas', CalendarDateKind.inCinemas),
    ('digitalRelease', CalendarDateKind.digitalRelease),
    ('physicalRelease', CalendarDateKind.physicalRelease),
  ])
    if (record[field] case final String date)
      CalendarEvent(
        itemRef: radarr.itemOf(record['id']! as int),
        title: record['title']! as String,
        date: DateTime.parse(date),
        dateKind: kind,
        state: _state(record),
      ),
];

List<CalendarEvent> _episodeEvents(JsonObject record) => [
  if (record['airDateUtc'] case final String date)
    CalendarEvent(
      itemRef: sonarr.itemOf(record['id']! as int),
      title: record['title']! as String,
      date: DateTime.parse(date),
      dateKind: CalendarDateKind.airDate,
      state: _state(record),
    ),
];

LibraryItem _movie(JsonObject record) {
  final title = record['title'];
  if (title is! String) throw const FormatException('No title');
  return Movie(
    ref: radarr.itemOf(record['id']! as int),
    title: title,
    sortTitle: title,
    monitored: record['monitored']! as bool,
    state: _state(record),
  );
}

LibraryItem _episode(JsonObject record) {
  final title = record['title'];
  if (title is! String) throw const FormatException('No title');
  return Episode(
    ref: sonarr.itemOf(record['id']! as int),
    title: title,
    sortTitle: title,
    monitored: record['monitored']! as bool,
    state: _state(record),
    seasonNumber: record['seasonNumber']! as int,
    episodeNumber: record['episodeNumber']! as int,
    hasFile: record['hasFile']! as bool,
  );
}
