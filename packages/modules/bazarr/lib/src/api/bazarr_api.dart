/// The requests the module makes to Bazarr, one method for each.
library;

import 'dart:convert';

import 'package:core/core.dart';

/// A manual search is answered once every provider has been asked.
const _searchTimeout = Duration(minutes: 2);

String _plural(SubtitleMediaType kind) => switch (kind) {
  SubtitleMediaType.movie => 'movies',
  SubtitleMediaType.episode => 'episodes',
};

// The one spelling `PATCH subtitles` understands; the others accept it too.
String _flag(bool value) => value ? 'True' : 'False';

Map<String, List<String>> _single(Map<String, String> query) => {
  for (final MapEntry(:key, :value) in query.entries) key: [value],
};

/// A web page where data was expected, whatever its content type says. Bazarr
/// answers a path it does not have with its web interface.
bool isWebPage(String text) => text.trimLeft().startsWith('<');

/// Bazarr's interface, below the instance's address.
///
/// A read gives the decoded body to `decode`, which throws [FormatException]
/// for one it cannot understand. A write is sent once and is not repeated.
final class BazarrApi {
  /// The interface reached through [_http].
  const BazarrApi(this._http);

  final ServiceHttpClient _http;

  /// `GET series` or `movies`, [length] entries from [start]. Without a length
  /// the server sends the whole library.
  ServiceResult<T> titles<T>(
    String path,
    T Function(Object? json) decode, {
    required int start,
    required int length,
  }) => _read(path, decode, query: {'start': '$start', 'length': '$length'});

  /// `GET series?seriesid[]=`.
  ServiceResult<T> series<T>(int seriesId, T Function(Object? json) decode) =>
      _read('series', decode, query: {'seriesid[]': '$seriesId'});

  /// `GET movies?radarrid[]=`.
  ServiceResult<T> movie<T>(int radarrId, T Function(Object? json) decode) =>
      _read('movies', decode, query: {'radarrid[]': '$radarrId'});

  /// `GET episodes?seriesid[]=`.
  ServiceResult<T> episodes<T>(int seriesId, T Function(Object? json) decode) =>
      _read('episodes', decode, query: {'seriesid[]': '$seriesId'});

  /// `GET episodes?episodeid[]=`.
  ServiceResult<T> episode<T>(int episodeId, T Function(Object? json) decode) =>
      _read('episodes', decode, query: {'episodeid[]': '$episodeId'});

  /// `GET movies/wanted` or `episodes/wanted`.
  ServiceResult<T> wanted<T>(
    SubtitleMediaType kind,
    T Function(Object? json) decode, {
    required int start,
    required int length,
  }) => titles('${_plural(kind)}/wanted', decode, start: start, length: length);

  /// `GET movies/history` or `episodes/history`.
  ServiceResult<T> history<T>(
    SubtitleMediaType kind,
    T Function(Object? json) decode, {
    required int start,
    required int length,
  }) =>
      titles('${_plural(kind)}/history', decode, start: start, length: length);

  /// `GET providers/movies` or `providers/episodes`: a manual search. [id] is
  /// the movie's or the episode's.
  ServiceResult<T> providers<T>(
    SubtitleMediaType kind,
    int id,
    T Function(Object? json) decode,
  ) => _read(
    'providers/${_plural(kind)}',
    decode,
    query: {
      switch (kind) {
        SubtitleMediaType.movie => 'radarrid',
        SubtitleMediaType.episode => 'episodeid',
      }: '$id',
    },
    timeout: _searchTimeout,
  );

  /// `PATCH movies/subtitles` or `episodes/subtitles`: an automatic search.
  /// [ids] name the movie, or the series and episode.
  ServiceResult<void> search(
    SubtitleMediaType kind,
    Map<String, String> ids,
    SubtitleLanguage language,
  ) => _write(
    HttpMethod.patch,
    '${_plural(kind)}/subtitles',
    query: ids,
    form: _language(language),
  );

  /// `POST providers/movies` or `providers/episodes`: downloads a candidate of
  /// a manual search.
  ServiceResult<void> download(
    SubtitleMediaType kind,
    Map<String, String> ids,
    SubtitleCandidate candidate,
  ) => _write(
    HttpMethod.post,
    'providers/${_plural(kind)}',
    query: ids,
    form: {
      'hi': _flag(candidate.language.hi),
      'forced': _flag(candidate.language.forced),
      'original_format': candidate.originalFormat,
      'provider': candidate.provider,
      'subtitle': candidate.token,
    },
  );

  /// `DELETE movies/subtitles` or `episodes/subtitles`.
  ServiceResult<void> delete(Map<String, String> ids, SubtitleFile file) =>
      _write(
        HttpMethod.delete,
        '${_plural(file.mediaType)}/subtitles',
        query: ids,
        form: {..._language(file.language), 'path': file.path},
      );

  /// `PATCH subtitles` with the action `sync`, the only one sent.
  ServiceResult<void> sync(SubtitleFile file) => _write(
    HttpMethod.patch,
    'subtitles',
    query: {'action': 'sync'},
    form: {
      'type': switch (file.mediaType) {
        SubtitleMediaType.movie => 'movie',
        SubtitleMediaType.episode => 'episode',
      },
      'id': '${file.mediaId}',
      ..._language(file.language),
      'path': file.path,
    },
  );

  Map<String, String> _language(SubtitleLanguage language) => {
    'language': language.code,
    'forced': _flag(language.forced),
    'hi': _flag(language.hi),
  };

  ServiceResult<T> _read<T>(
    String path,
    T Function(Object? json) decode, {
    required Map<String, String> query,
    Duration? timeout,
  }) async {
    final answer = await _http.send(
      ServiceRequest(
        HttpMethod.get,
        'api/$path',
        query: _single(query),
        timeout: timeout,
      ),
    );
    switch (answer) {
      case Err(:final error):
        return Err(error.failure);
      case Ok(:final value):
        final text = value.text;
        if (isWebPage(text)) return const Err(ProxyInterception());
        try {
          return Ok(decode(jsonDecode(text)));
        } on FormatException {
          // The exception quotes the body, so it goes no further.
          return const Err(MalformedResponse());
        }
    }
  }

  ServiceResult<void> _write(
    HttpMethod method,
    String path, {
    required Map<String, String> query,
    required Map<String, String> form,
  }) async {
    final answer = await _http.send(
      ServiceRequest(
        method,
        'api/$path',
        query: _single(query),
        body: FormBody(form),
      ),
    );
    switch (answer) {
      case Err(:final error):
        return Err(error.failure);
      case Ok(:final value):
        // 204 with nothing, or `null` from the manual download of 1.5.
        return switch (value.text.trim()) {
          '' || 'null' => const Ok(null),
          final text when isWebPage(text) => const Err(ProxyInterception()),
          _ => const Err(MalformedResponse()),
        };
    }
  }
}
