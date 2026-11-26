/// Lidarr's calendar, imports and wanted lists, all of albums. Health and disk
/// space are the shared Servarr ones as they are.
///
/// The state of an album depends on the download queue, so
/// [LidarrCalendarAdapter.events] and the wanted lists read it too, and fail if
/// that read fails: a queued album would otherwise be shown as missing. An
/// import has no state, so the two reads of imports leave the queue alone.
library;

import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../api/lidarr_api.dart';
import '../models/json_fields.dart';
import '../models/library_record.dart';

const _includeArtist = {
  'includeArtist': ['true'],
};

/// Upcoming albums and the albums imported.
final class LidarrCalendarAdapter implements CalendarProvider {
  /// Reads with [_api].
  LidarrCalendarAdapter(this._api);

  final LidarrApi _api;

  /// The monitored albums released in the window.
  @override
  ServiceResult<List<CalendarEvent>> events(
    DateTime from,
    DateTime to,
  ) async => switch (await _queued(_api)) {
    // Before the calendar, so that a download that ends between the two reads
    // does not leave its album missing.
    Ok(:final value) => _calendar(downloading: value).events(from, to),
    Err(:final error) => Err(error),
  };

  /// Lidarr records an import for each track; each album is listed once.
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
        calendarQuery: _includeArtist,
        importTitle: _importTitle,
        historyQuery: const {
          ..._includeArtist,
          'includeAlbum': ['true'],
        },
        importEvent: 'trackFileImported',
      );

  /// A record of `GET calendar`. An album without a release date is left out.
  List<CalendarEvent> _events(
    JsonObject record, {
    required Set<int> downloading,
  }) {
    final id = requireInt(record, 'id');
    final released = optionalTime(record, 'releaseDate');
    if (released == null) return const [];
    return [
      CalendarEvent(
        itemRef: _api.albumRef(id),
        title: _title(embeddedArtistName(record), requireText(record, 'title')),
        date: released,
        dateKind: CalendarDateKind.releaseDate,
        state: containerState(record, downloading: downloading.contains(id)),
      ),
    ];
  }
}

/// Monitored albums without all their files, and below their cutoff, latest
/// released first. A page is not the library, so nothing is cached.
final class LidarrWantedAdapter implements WantedProvider {
  /// Reads with [_api].
  LidarrWantedAdapter(this._api);

  final LidarrApi _api;

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
        item: (record) => _album(record, downloading: downloading),
        // Stated: the cutoff list has no order of its own.
        query: const {
          ..._includeArtist,
          'sortKey': ['releaseDate'],
          'sortDirection': ['descending'],
        },
      ),
    ),
  };

  /// A record of `GET wanted/missing` or `GET wanted/cutoff`.
  Album _album(JsonObject record, {required Set<int> downloading}) {
    final id = requireInt(record, 'id');
    return readAlbum(
      record,
      ref: _api.albumRef(id),
      artist: _api.artistRef(requireInt(record, 'artistId')),
      artistName: embeddedArtistName(record),
      state: containerState(record, downloading: downloading.contains(id)),
    );
  }
}

/// The ids of the albums in the download queue.
Future<Result<Set<int>, ServiceFailure>> _queued(LidarrApi api) async =>
    switch (await api.queue()) {
      Ok(:final value) => Ok({
        for (final item in value) ?item.itemRef?.remoteId,
      }),
      // NotFound would say that what was asked for is gone.
      Err(error: NotFound()) => const Err(ServerError(statusCode: 404)),
      Err(:final error) => Err(error),
    };

/// The title of a history record: of its album, or the release's name if the
/// record does not name one.
String _importTitle(JsonObject record) {
  final album = optionalText(objectIn(record, 'album'), 'title');
  if (album == null) return optionalText(record, 'sourceTitle') ?? '';
  return _title(optionalText(objectIn(record, 'artist'), 'artistName'), album);
}

/// What names an album among those of other artists.
String _title(String? artist, String album) => [?artist, album].join(' - ');
