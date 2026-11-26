/// Sonarr's calendar, imports and wanted lists. Health and disk space are the
/// shared Servarr ones as they are.
///
/// The state of an episode depends on the download queue, so
/// [SonarrCalendarAdapter.events] and the wanted lists read it too, and fail if
/// that read fails: a queued episode would otherwise be shown as missing. An
/// import has no state, so the two reads of imports leave the queue alone.
library;

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../api/sonarr_api.dart';
import '../models/episode_record.dart';
import '../models/json_fields.dart';

const _includeSeries = {
  'includeSeries': ['true'],
};

/// Upcoming episodes and the episodes imported.
final class SonarrCalendarAdapter implements CalendarProvider {
  /// Reads with [_api].
  SonarrCalendarAdapter(this._api);

  final SonarrApi _api;

  /// The monitored episodes airing in the window, each at the instant it airs.
  @override
  ServiceResult<List<CalendarEvent>> events(
    DateTime from,
    DateTime to,
  ) async => switch (await _queued(_api)) {
    // Before the calendar, so that a download that ends between the two reads
    // does not leave its episode missing.
    Ok(:final value) => _calendar(downloading: value).events(from, to),
    Err(:final error) => Err(error),
  };

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
        calendarQuery: _includeSeries,
        importTitle: _importTitle,
        historyQuery: const {
          ..._includeSeries,
          'includeEpisode': ['true'],
        },
      );

  /// A record of `GET calendar`. `airDate`, the day where the network is, is
  /// not used: an episode without an instant is left out.
  List<CalendarEvent> _events(
    JsonObject record, {
    required Set<int> downloading,
  }) {
    final id = requireInt(record, 'id');
    final number = _number(record);
    final aired = DateTime.tryParse(optionalText(record, 'airDateUtc') ?? '');
    if (aired == null) return const [];
    return [
      CalendarEvent(
        itemRef: _api.episodeRef(id),
        title: _title(_seriesTitle(record), number, record),
        date: aired.toUtc(),
        dateKind: CalendarDateKind.airDate,
        state: episodeState(
          record,
          downloading: downloading.contains(id),
          now: DateTime.now().toUtc(),
        ),
      ),
    ];
  }
}

/// Monitored episodes without a file, and below their cutoff, latest aired
/// first. A page is not the library, so nothing is cached.
final class SonarrWantedAdapter implements WantedProvider {
  /// Reads with [_api].
  SonarrWantedAdapter(this._api);

  final SonarrApi _api;

  @override
  ServiceResult<ResultPage<LibraryItem>> missing({int page = 1}) =>
      _read((wanted) => wanted.missing(page: page));

  @override
  ServiceResult<ResultPage<LibraryItem>> cutoffUnmet({int page = 1}) => _read(
    (wanted) => wanted.cutoffUnmet(page: page),
    // These have files; the missing list takes no such parameter.
    query: const {
      'includeEpisodeFile': ['true'],
    },
  );

  ServiceResult<ResultPage<LibraryItem>> _read(
    ServiceResult<ResultPage<LibraryItem>> Function(ServarrWanted wanted)
    list, {
    Map<String, List<String>> query = const {},
  }) async {
    switch (await _queued(_api)) {
      case Err(:final error):
        return Err(error);
      case Ok(value: final downloading):
        return list(
          ServarrWanted(
            _api.shared,
            item: (record) => _episode(record, downloading: downloading),
            query: {
              ..._includeSeries,
              'includeImages': ['true'],
              'sortKey': ['episodes.airDateUtc'],
              'sortDirection': ['descending'],
              ...query,
            },
          ),
        );
    }
  }

  /// A record of `GET wanted/missing` or `GET wanted/cutoff`.
  Episode _episode(JsonObject record, {required Set<int> downloading}) {
    final id = requireInt(record, 'id');
    return readEpisode(
      record,
      ref: _api.episodeRef(id),
      series: _api.seriesRef(requireInt(record, 'seriesId')),
      seriesTitle: _seriesTitle(record),
      state: episodeState(
        record,
        downloading: downloading.contains(id),
        now: DateTime.now().toUtc(),
      ),
    );
  }
}

/// The ids of the episodes in the download queue.
Future<Result<Set<int>, ServiceFailure>> _queued(SonarrApi api) async =>
    switch (await api.queue()) {
      Ok(:final value) => Ok({
        for (final item in value) ?item.itemRef?.remoteId,
      }),
      // NotFound would say that what was asked for is gone.
      Err(error: NotFound()) => const Err(ServerError(statusCode: 404)),
      Err(:final error) => Err(error),
    };

/// The title of a history record: of its episode, or the release's name if the
/// record does not say which series and episode that is.
String _importTitle(JsonObject record) {
  final series = _seriesTitle(record);
  if (record['episode'] case final JsonObject episode
      when series != null &&
          episode['seasonNumber'] is int &&
          episode['episodeNumber'] is int) {
    return _title(series, _number(episode), episode);
  }
  return optionalText(record, 'sourceTitle') ?? '';
}

String? _seriesTitle(JsonObject record) => switch (record['series']) {
  final JsonObject series => optionalText(series, 'title'),
  _ => null,
};

/// The number of an episode, as `S06E01`.
String _number(JsonObject episode) {
  String part(String field) => '${requireInt(episode, field)}'.padLeft(2, '0');
  return 'S${part('seasonNumber')}E${part('episodeNumber')}';
}

/// What names an episode among those of other series: what is known of the
/// series, its number and its own title.
String _title(String? series, String number, JsonObject episode) =>
    [?series, number, ?optionalText(episode, 'title')].join(' - ');
