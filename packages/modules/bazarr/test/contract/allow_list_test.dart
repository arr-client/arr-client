import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

ServiceRequest _send(
  HttpMethod method,
  String path, {
  Map<String, String> query = const {},
  Map<String, String>? form,
}) => ServiceRequest(
  method,
  'api/$path',
  query: {
    for (final MapEntry(:key, :value) in query.entries) key: [value],
  },
  body: form == null ? null : FormBody(form),
);

const _movie = {'radarrid': '1'};
const _episode = {'seriesid': '1', 'episodeid': '2'};
const _language = {'language': 'en', 'forced': 'False', 'hi': 'False'};
const _file = {..._language, 'path': '/a.srt'};
const _candidate = {
  'hi': 'False',
  'forced': 'False',
  'original_format': 'False',
  'provider': 'p',
  'subtitle': 's',
};
const _sync = {..._file, 'type': 'movie', 'id': '1'};

void main() {
  test('permits what is listed', () {
    final listed = [
      _send(HttpMethod.get, 'system/status'),
      _send(HttpMethod.get, 'series', query: {'start': '0', 'length': '50'}),
      _send(HttpMethod.get, 'series', query: {'seriesid[]': '1'}),
      _send(HttpMethod.get, 'movies', query: {'start': '0', 'length': '50'}),
      _send(HttpMethod.get, 'movies', query: {'radarrid[]': '1'}),
      _send(HttpMethod.get, 'episodes', query: {'seriesid[]': '1'}),
      _send(HttpMethod.get, 'episodes', query: {'episodeid[]': '2'}),
      for (final path in [
        'episodes/wanted',
        'movies/wanted',
        'episodes/history',
        'movies/history',
      ])
        _send(HttpMethod.get, path, query: {'start': '0', 'length': '50'}),
      _send(HttpMethod.get, 'providers/episodes', query: {'episodeid': '2'}),
      _send(HttpMethod.get, 'providers/movies', query: _movie),
      for (final (path, ids) in [
        ('episodes', _episode),
        ('movies', _movie),
      ]) ...[
        _send(HttpMethod.patch, '$path/subtitles', query: ids, form: _language),
        _send(HttpMethod.delete, '$path/subtitles', query: ids, form: _file),
        _send(HttpMethod.post, 'providers/$path', query: ids, form: _candidate),
      ],
      _send(
        HttpMethod.patch,
        'subtitles',
        query: {'action': 'sync'},
        form: _sync,
      ),
    ];
    for (final request in listed) {
      expect(allowList.permits(request), isTrue, reason: request.path);
    }
  });

  test('refuses what is not listed', () {
    final unlisted = [
      // Configuration, which holds the keys of the connected services.
      _send(HttpMethod.get, 'system/settings'),
      _send(HttpMethod.post, 'system/settings', form: {}),
      _send(HttpMethod.get, 'system/logs'),
      _send(HttpMethod.post, 'system/tasks', form: {'taskid': 'backup'}),
      _send(HttpMethod.post, 'system', query: {'action': 'restart'}),
      // Languages profiles of titles, and actions on whole titles.
      for (final path in ['series', 'movies']) ...[
        _send(HttpMethod.post, path, form: {'profileid': '1'}),
        _send(HttpMethod.patch, path, form: {'action': 'search-wanted'}),
      ],
      // Uploads, and the blacklist.
      for (final path in ['episodes', 'movies']) ...[
        _send(HttpMethod.post, '$path/subtitles', form: _language),
        _send(HttpMethod.post, '$path/blacklist', form: {}),
        _send(HttpMethod.delete, '$path/blacklist', form: {}),
      ],
      _send(HttpMethod.post, 'providers', form: {'action': 'reset'}),
      // The same path does much more than synchronizing.
      for (final action in ['translate', 'extract', 'remove_HI'])
        _send(
          HttpMethod.patch,
          'subtitles',
          query: {'action': action},
          form: _sync,
        ),
      _send(HttpMethod.patch, 'subtitles', form: _sync),
      _send(
        HttpMethod.patch,
        'subtitles',
        query: {'action': 'sync'},
        form: {..._sync, 'action': 'translate'},
      ),
      // A write that does not name its target.
      _send(HttpMethod.delete, 'movies/subtitles', form: _file),
      _send(
        HttpMethod.delete,
        'episodes/subtitles',
        query: {'seriesid': '1'},
        form: _file,
      ),
      _send(HttpMethod.delete, 'movies/subtitles', query: _movie),
      _send(
        HttpMethod.delete,
        'movies/subtitles',
        query: _movie,
        form: {..._file, 'path': ''},
      ),
      // Paths stay out of addresses, which servers and proxies log.
      _send(
        HttpMethod.delete,
        'movies/subtitles',
        query: {..._movie, ..._file},
      ),
      // The key goes in a header.
      _send(HttpMethod.get, 'system/status', query: {'apikey': 'k'}),
    ];
    for (final request in unlisted) {
      expect(
        allowList.permits(request),
        isFalse,
        reason: '${request.method.name} ${request.path} ${request.query}',
      );
    }
  });
}
