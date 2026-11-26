import 'package:core/core.dart';

import '../api/bazarr_api.dart';
import '../models/bazarr_records.dart';
import '../subtitles_route.dart';

/// How many entries a page of a list has.
const _pageLength = 50;

/// What a search or a download acts on: its kind, the id of the movie or
/// episode, and the query naming it in a write.
typedef _Target = ({SubtitleMediaType kind, int id, Map<String, String> query});

/// Null for a series, which the server neither searches nor downloads for.
_Target? _target(SubtitleMedia media) => switch (media) {
  SubtitleMedia(kind: SubtitleKind.movie, :final radarrId?) => (
    kind: SubtitleMediaType.movie,
    id: radarrId,
    query: {'radarrid': '$radarrId'},
  ),
  SubtitleMedia(
    kind: SubtitleKind.episode,
    :final seriesId?,
    :final episodeId?,
  ) =>
    (
      kind: SubtitleMediaType.episode,
      id: episodeId,
      query: {'seriesid': '$seriesId', 'episodeid': '$episodeId'},
    ),
  _ => null,
};

/// What gets a request the server has no way to take. Nothing is sent.
const _unsupported = Validation([]);

/// Subtitles of one instance of Bazarr.
///
/// Bazarr 1.6 accepts a search, a download or a synchronization before doing
/// it: success then means it was queued, and only the server's log tells
/// whether it worked.
final class BazarrSubtitleProvider implements SubtitleProvider {
  /// The subtitles of the instance [instanceId], through [_api].
  BazarrSubtitleProvider(this._api, this.instanceId);

  final BazarrApi _api;

  /// The instance served.
  final String instanceId;

  @override
  ServiceResult<ResultPage<SubtitleTitle>> browseSeries({int page = 1}) =>
      _titles('series', seriesTitle, page);

  @override
  ServiceResult<ResultPage<SubtitleTitle>> browseMovies({int page = 1}) =>
      _titles('movies', movieTitle, page);

  ServiceResult<ResultPage<SubtitleTitle>> _titles(
    String path,
    SubtitleTitle Function(JsonObject record) read,
    int page,
  ) => _api.titles(
    path,
    (json) => pageOf(json, read, page: page, length: _pageLength),
    start: (page - 1) * _pageLength,
    length: _pageLength,
  );

  @override
  ServiceResult<List<SubtitleTitle>> browseEpisodes(int seriesId) =>
      _api.episodes(
        seriesId,
        (json) => dataRecords(json).map(episodeTitle).toList(),
      );

  @override
  ServiceResult<ResultPage<SubtitleWant>> wanted(
    SubtitleMediaType type, {
    int page = 1,
  }) => _api.wanted(
    type,
    (json) => pageOf(
      json,
      (record) => wantRecord(record, type),
      page: page,
      length: _pageLength,
    ),
    start: (page - 1) * _pageLength,
    length: _pageLength,
  );

  @override
  ServiceResult<ResultPage<SubtitleHistoryEvent>> history(
    SubtitleMediaType type, {
    int page = 1,
  }) => _api.history(
    type,
    (json) => pageOf(
      json,
      (record) => historyRecord(record, type),
      page: page,
      length: _pageLength,
    ),
    start: (page - 1) * _pageLength,
    length: _pageLength,
  );

  @override
  ServiceResult<SubtitleTitle> forMedia(SubtitleMedia media) async {
    final found = await _recordsOf(media);
    return switch (found) {
      Err(:final error) => Err(error),
      // The server answers an id it does not know with an empty list.
      Ok(:final value) => switch (value
          .where((title) => title.media == media)
          .firstOrNull) {
        final title? => Ok(title),
        null => const Err(NotFound()),
      },
    };
  }

  /// What the server answers when asked for [media] alone.
  ServiceResult<List<SubtitleTitle>> _recordsOf(SubtitleMedia media) async {
    List<SubtitleTitle> movies(Object? json) =>
        dataRecords(json).map(movieTitle).toList();
    List<SubtitleTitle> series(Object? json) =>
        dataRecords(json).map(seriesTitle).toList();
    List<SubtitleTitle> episodes(Object? json) =>
        dataRecords(json).map(episodeTitle).toList();

    return switch (media) {
      SubtitleMedia(kind: SubtitleKind.movie, :final radarrId?) => _api.movie(
        radarrId,
        movies,
      ),
      SubtitleMedia(kind: SubtitleKind.series, :final seriesId?) => _api.series(
        seriesId,
        series,
      ),
      SubtitleMedia(kind: SubtitleKind.episode, :final episodeId?) =>
        _api.episode(episodeId, episodes),
      // No constructor of [SubtitleMedia] leaves out its id.
      _ => const Err(_unsupported),
    };
  }

  @override
  ServiceResult<void> autoSearch(
    SubtitleMedia media,
    SubtitleLanguage language,
  ) async => switch (_target(media)) {
    final target? => _api.search(target.kind, target.query, language),
    null => const Err(_unsupported),
  };

  @override
  ServiceResult<List<SubtitleCandidate>> manualSearch(
    SubtitleMedia media,
  ) async => switch (_target(media)) {
    final target? => _api.providers(
      target.kind,
      target.id,
      (json) => dataRecords(json).map(candidateRecord).toList(),
    ),
    null => const Err(_unsupported),
  };

  @override
  ServiceResult<void> download(
    SubtitleMedia media,
    SubtitleCandidate candidate,
  ) async => switch (_target(media)) {
    final target? => _api.download(target.kind, target.query, candidate),
    null => const Err(_unsupported),
  };

  /// An episode's file without its series sends nothing and fails with
  /// [Validation].
  @override
  ServiceResult<void> delete(SubtitleFile file) async =>
      switch ((file.mediaType, file.seriesId)) {
        (SubtitleMediaType.movie, _) => _api.delete({
          'radarrid': '${file.mediaId}',
        }, file),
        (SubtitleMediaType.episode, final seriesId?) => _api.delete({
          'seriesid': '$seriesId',
          'episodeid': '${file.mediaId}',
        }, file),
        (SubtitleMediaType.episode, null) => const Err(_unsupported),
      };

  @override
  ServiceResult<void> sync(SubtitleFile file) => _api.sync(file);

  @override
  ModuleRoute entryRoute() =>
      ModuleRoute(instanceId: instanceId, path: subtitlesPattern);
}
