/// Reading Bazarr's records. What a record cannot do without throws
/// [FormatException]; anything else of the wrong type counts as left out.
library;

import 'package:core/core.dart';

JsonObject _object(Object? json) =>
    json is JsonObject ? json : throw const FormatException('Not an object');

List<JsonObject> _objects(Object? json) => json is List<Object?>
    ? [for (final entry in json) _object(entry)]
    : throw const FormatException('Not a list');

/// The records of an answer's `data`.
List<JsonObject> dataRecords(Object? json) => _objects(_object(json)['data']);

/// One page of a list the server pages: its records, out of `total`.
ResultPage<T> pageOf<T>(
  Object? json,
  T Function(JsonObject record) read, {
  required int page,
  required int length,
}) {
  final total = _requireInt(_object(json), 'total');
  return ResultPage(
    items: dataRecords(json).map(read).toList(),
    page: page,
    hasMore: page * length < total,
  );
}

int _requireInt(JsonObject record, String field) => switch (record[field]) {
  final int value => value,
  _ => throw const FormatException('A number is missing'),
};

String _requireString(JsonObject record, String field) =>
    switch (record[field]) {
      final String value => value,
      _ => throw const FormatException('A text is missing'),
    };

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

List<String> _texts(Object? value) =>
    value is List<Object?> ? value.whereType<String>().toList() : const [];

/// A language as `{code2, forced, hi}`.
SubtitleLanguage _language(JsonObject record) => SubtitleLanguage(
  code: _requireString(record, 'code2'),
  forced: record['forced'] == true,
  hi: record['hi'] == true,
);

List<SubtitleLanguage> _missing(JsonObject record) =>
    switch (record['missing_subtitles']) {
      final List<Object?> list => _objects(list).map(_language).toList(),
      _ => const [],
    };

/// The files among a record's `subtitles`. A track inside the video has no
/// path, and can be neither deleted nor synchronized.
List<SubtitleFile> _files(
  JsonObject record,
  SubtitleMediaType type,
  int mediaId, {
  int? seriesId,
}) => switch (record['subtitles']) {
  final List<Object?> list => [
    for (final file in _objects(list))
      if (_text(file['path']) case final path?)
        SubtitleFile(
          mediaType: type,
          mediaId: mediaId,
          seriesId: seriesId,
          path: path,
          language: _language(file),
        ),
  ],
  _ => const [],
};

int? _year(Object? value) => value is String ? int.tryParse(value) : null;

/// A record of `GET movies`.
SubtitleTitle movieTitle(JsonObject record) {
  final id = _requireInt(record, 'radarrId');
  final missing = _missing(record);
  return SubtitleTitle(
    media: SubtitleMedia.movie(id),
    title: _requireString(record, 'title'),
    year: _year(record['year']),
    missing: missing,
    missingCount: missing.length,
    files: _files(record, SubtitleMediaType.movie, id),
  );
}

/// A record of `GET series`.
SubtitleTitle seriesTitle(JsonObject record) => SubtitleTitle(
  media: SubtitleMedia.series(_requireInt(record, 'sonarrSeriesId')),
  title: _requireString(record, 'title'),
  year: _year(record['year']),
  missingCount: switch (record['episodeMissingCount']) {
    final int count => count,
    _ => 0,
  },
);

/// A record of `GET episodes`, titled with its number as the server writes it
/// in the wanted and history lists.
SubtitleTitle episodeTitle(JsonObject record) {
  final seriesId = _requireInt(record, 'sonarrSeriesId');
  final episodeId = _requireInt(record, 'sonarrEpisodeId');
  final missing = _missing(record);
  return SubtitleTitle(
    media: SubtitleMedia.episode(seriesId: seriesId, episodeId: episodeId),
    title:
        '${_requireInt(record, 'season')}x${_requireInt(record, 'episode')}'
        ' - ${_requireString(record, 'title')}',
    missing: missing,
    missingCount: missing.length,
    files: _files(
      record,
      SubtitleMediaType.episode,
      episodeId,
      seriesId: seriesId,
    ),
  );
}

/// What a wanted or history record is about.
SubtitleMedia _media(JsonObject record, SubtitleMediaType type) =>
    switch (type) {
      SubtitleMediaType.movie => SubtitleMedia.movie(
        _requireInt(record, 'radarrId'),
      ),
      SubtitleMediaType.episode => SubtitleMedia.episode(
        seriesId: _requireInt(record, 'sonarrSeriesId'),
        episodeId: _requireInt(record, 'sonarrEpisodeId'),
      ),
    };

/// The title of a wanted or history record.
String _listedTitle(JsonObject record, SubtitleMediaType type) =>
    switch (type) {
      SubtitleMediaType.movie => _requireString(record, 'title'),
      SubtitleMediaType.episode => [
        _requireString(record, 'seriesTitle'),
        ?_text(record['episode_number']),
        ?_text(record['episodeTitle']),
      ].join(' - '),
    };

/// A record of `GET movies/wanted` or `episodes/wanted`.
SubtitleWant wantRecord(JsonObject record, SubtitleMediaType type) =>
    SubtitleWant(
      media: _media(record, type),
      title: _listedTitle(record, type),
      missing: _missing(record),
    );

/// A record of `GET movies/history` or `episodes/history`.
SubtitleHistoryEvent historyRecord(JsonObject record, SubtitleMediaType type) =>
    SubtitleHistoryEvent(
      // The server gives no time a program can read.
      whenText: [
        ?_text(record['timestamp']),
        ?_text(record['parsed_timestamp']),
      ].join(', '),
      mediaRef: _media(record, type),
      title: _listedTitle(record, type),
      // An entry without a language has an object of nulls here; one such entry
      // does not hide the others.
      language: switch (record['language']) {
        final JsonObject language when language['code2'] is String => _language(
          language,
        ),
        _ => const SubtitleLanguage(code: ''),
      },
      provider: _text(record['provider']),
      score: _text(record['score']),
      action: _text(record['description']) ?? '',
    );

/// A record of a manual search. Its flags are the texts `True` and `False`,
/// and its language may carry them too, as in `pt-BR:hi`.
SubtitleCandidate candidateRecord(JsonObject record) => SubtitleCandidate(
  provider: _requireString(record, 'provider'),
  language: SubtitleLanguage(
    code: _requireString(record, 'language').split(':').first,
    forced: record['forced'] == 'True',
    hi: record['hearing_impaired'] == 'True',
  ),
  score: switch (record['score']) {
    final num score => score.toDouble(),
    _ => throw const FormatException('A score is missing'),
  },
  matches: _texts(record['matches']),
  dontMatches: _texts(record['dont_matches']),
  // Bazarr 1.5 has none for a languages profile that never set it.
  originalFormat: switch (record['original_format']) {
    null => 'False',
    _ => _requireString(record, 'original_format'),
  },
  token: _requireString(record, 'subtitle'),
);
