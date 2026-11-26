// Every secret, host and person here is invented. Hosts use reserved names and addresses, and no
// value has the format of a real provider's token.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../sanitize_fixture.dart';

const _secrets = [
  // Keys, tokens, passwords, cookies
  'fakefakefakefakefakefakefake0000',
  'FAKE-token-not-real',
  'hunter2-fake',
  'correcthorsefake',
  'SID=fake-session-value; path=/',
  'Bearer fake-bearer-value',
  'Basic ZmFrZS11c2VyOmZha2UtcGFzcw==',
  // The same, encoded
  'ZmFrZS1hcGkta2V5LW5vdC1yZWFs',
  'fake%2Dapi%2Dkey',
  '{"apiKey":"FAKE-nested-json-key"}',
  // URLs with credentials or query secrets
  'http://fakeuser:fakepass@nas.invalid:8989/sonarr',
  'https://indexer.example/api?apikey=fake-query-key&t=search',
  'magnet:?xt=urn:btih:fake&tr=udp://tracker.example/fakepasskey',
  '//nas.invalid/share',
  '/MediaCover/1/poster.jpg?apikey=fake-cover-key',
  // Hosts and addresses
  'nas.invalid',
  'fakehostname',
  'my-nas.local:7878',
  '192.0.2.17',
  '10.0.0.1',
  '192.168.100.200',
  '2001:db8::dead:beef',
  'fe80::1%eth0',
  '02:00:5e:10:00:01',
  // Paths
  '/home/fakeperson/media/Some Film (2001)/film.mkv',
  r'C:\Users\FakePerson\Downloads\film.mkv',
  r'\\FAKENAS\media\film.mkv',
  '~/fakeperson/media',
  // People
  'fakeperson@mail.example',
  'fakeperson',
  'Fake Person',
  'FakePerson',
  'Connection to fakehostname refused for fakeperson',
];

String _sanitize(Object? json) =>
    jsonEncode(FixtureSanitizer().sanitizeJson(json));

/// The strings and keys of [json], at any depth.
Iterable<String> _strings(Object? json) sync* {
  if (json is String) yield json;
  if (json is List<Object?>) {
    for (final item in json) {
      yield* _strings(item);
    }
  }
  if (json is Map<String, Object?>) {
    yield* json.keys;
    for (final value in json.values) {
      yield* _strings(value);
    }
  }
}

void _expectNoSecrets(Object? input) {
  final output = FixtureSanitizer().sanitizeJson(input);
  for (final out in _strings(output)) {
    for (final secret in _secrets) {
      expect(out, isNot(contains(secret)));
    }
    expect(out.toLowerCase(), isNot(contains('fake')));
  }
}

void main() {
  group('secrets do not survive', () {
    // Field names the sanitizer treats specially, and some it has never heard of.
    const fields = [
      'apiKey', 'password', 'cookie', 'host', 'path', 'userName', 'email',
      'status', 'state', 'type', 'source', 'name', 'title', 'message', 'value',
      'protocol', 'eventType', 'commandName', 'mode', 'result', 'version',
      'appVersion', 'imdbId', 'code2', 'hash', 'downloadId', 'guid', 'url',
      'remoteUrl', 'posterPath', 'added', 'timeleft', 'zzz', 'x_y', 'Weird',
      // A field name does not make its value safe.
      'tmdbId', 'id', 'quality', 'year',
      'forced', 'hearing_impaired', 'hi', 'original_format', 'language',
      'originalLanguage', 'airTime', 'runTime', 'finaleType',
      'appName', 'errorCode', 'propertyName', 'reason', 'releaseSource',
      'releaseType', 'indexerFlags', 'certification', 'audioCodec',
      'videoCodec', 'resolution', 'audioLanguages', 'subtitles', 'matches',
      'timestamp', 'parsed_timestamp', 'score', 'episode_number', 'sortKey',
      'size', 'age', 'isbn13', 'privacy', 'secondaryTypes', 'severity',
    ];

    for (final field in fields) {
      test('in a field called $field', () {
        for (final secret in _secrets) {
          _expectNoSecrets({field: secret});
          _expectNoSecrets({
            field: [secret],
          });
          _expectNoSecrets({
            'outer': [
              {
                field: {'deeper': secret},
              },
            ],
          });
        }
      });
    }

    test('as a bare string or list', () {
      _expectNoSecrets(_secrets);
      for (final secret in _secrets) {
        _expectNoSecrets(secret);
      }
    });

    test('as object keys', () {
      // Keys shaped like field names are the documented exception.
      final shaped = RegExp(r'^[A-Za-z_]\w*$');
      final keys = _secrets.where((s) => !shaped.hasMatch(s));
      _expectNoSecrets({for (final key in keys) key: 1});
      _expectNoSecrets({
        'trackers': {for (final key in keys) key: true},
      });
    });

    test('as keys that look like tokens or are very long', () {
      final out = _sanitize({
        'a1b2c3d4e5f6a7b8': 1,
        'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopq': 2,
      });
      expect(out, '{"redactedKey1":1,"redactedKey2":2}');
    });

    test('when text surrounds a harmless shape', () {
      for (final value in [
        '2020-01-01 fakeperson',
        'fakeperson\n2020-01-01',
        '2020-01-01\nfakeperson',
        '00:10:00 nas.invalid',
        '1.2.3-fakeperson',
        '/MediaCover/1/poster.jpg\nfakeperson',
      ]) {
        for (final field in ['added', 'version', 'url']) {
          _expectNoSecrets({field: value});
        }
      }
    });

    test('as an IPv4 address in a version field', () {
      for (final ip in ['10.0.0.1', '192.168.1.20', 'v192.0.2.1']) {
        expect(_sanitize({'version': ip}), isNot(contains(ip)));
        expect(() => FixtureSanitizer().sanitize(ip), _refuses);
      }
    });

    test('as enum words inside a private field', () {
      expect(
        _sanitize({
          'password': {'type': 'warning', 'since': '2020-01-01'},
        }),
        '{"password":{"type":"redacted","since":"redacted"}}',
      );
    });
  });

  group('private numbers', () {
    test('are zeroed by field name, however it is written', () {
      for (final field in [
        'password',
        'api_key',
        'ApiKey',
        'X-Api-Key',
        'port',
        'sslPort',
        'SSL_PORT',
        'pin',
        'plexId',
        'telegramChatId',
        'discordId',
        'uid',
        'jellyfinUserId',
        'ipAddress',
        'latitude',
        'authToken',
        'key',
      ]) {
        final out = FixtureSanitizer().sanitizeJson({field: 4242});
        expect((out! as Map<String, Object?>).values.single, 0, reason: field);
      }
    });

    test('are zeroed inside a private object', () {
      expect(
        _sanitize({
          'credentials': [
            {'id': 4242},
          ],
        }),
        '{"credentials":[{"id":0}]}',
      );
    });

    test('are zeroed in name and value settings', () {
      expect(_sanitize({'Name': 'x', 'Value': 4242}), isNot(contains('4242')));
      expect(
        _sanitize({
          'fields': [
            {'name': 'seedLimit', 'value': 4242},
            {
              'name': 'x',
              'value': [4242],
            },
          ],
        }),
        isNot(contains('4242')),
      );
    });
  });

  group('what contract tests need', () {
    test('keeps structure, numbers, booleans and null', () {
      const input = {
        'id': 7,
        'sizeleft': 1.5,
        'monitored': true,
        'importMode': 3,
        'report': 4,
        'overview': null,
        'title': '',
        'ratings': {'votes': 10, 'value': 7.5},
        'seasons': {'1': 2},
        'tags': <Object?>[],
      };
      expect(FixtureSanitizer().sanitizeJson(input), input);
    });

    test('keeps harmless strings in their fields', () {
      const input = {
        'added': '2024-03-01T10:11:12.345Z',
        'airDate': '2024-03-01',
        'timeleft': '1.02:03:04',
        'version': '4.0.15.2941',
        'appVersion': '5.3.1',
        'imdbId': 'tt0000001',
        'code2': 'en',
        'protocol': 'torrent',
        'state': 'stalledUP',
        'trackedDownloadState': 'importPending',
        'source': 'IndexerStatusCheck',
        'type': 'warning',
        'url': '/MediaCover/12/poster-500.jpg?lastWrite=638000000000000000',
      };
      expect(FixtureSanitizer().sanitizeJson(input), input);
    });

    test('keeps what Bazarr manual search results are sent back with', () {
      Map<String, Object?> result(String language) => {
        'forced': 'False',
        'hearing_impaired': 'True',
        'hi': 'False',
        'original_format': 'False',
        'language': language,
        'score': 96.5,
      };
      final input = {
        'data': [
          for (final language in ['en', 'eng', 'en:hi', 'fr:forced', 'pt-BR'])
            result(language),
          result('zh-Hant'),
        ],
      };
      expect(FixtureSanitizer().sanitizeJson(input), input);
    });

    test('keeps those values in their own fields and spelling only', () {
      for (final input in [
        {'title': 'True'},
        {'forced': 'true'},
        {'language': 'en:nas'},
        {'language': 'English (US)'},
        {'airTime': '25:00'},
        {'title': '21:00'},
        {'runTime': '42:75'},
        {'originalLanguage': 'nas1'},
        {'type': 'webrip.local'},
      ]) {
        expect(FixtureSanitizer().sanitizeJson(input), {
          input.keys.single: 'redacted-1',
        }, reason: '$input');
      }
    });

    test('keeps times and the original language', () {
      for (final input in [
        {'airTime': '21:00'},
        {'runTime': '42:15'},
        {'runTime': '5:07'},
        {'runTime': '1:02:03'},
        {'originalLanguage': 'en'},
      ]) {
        expect(FixtureSanitizer().sanitizeJson(input), input);
      }
    });

    test('keeps enum words of releases, credits, episodes and history', () {
      const words = {
        'source': ['webRip', 'webrip'],
        'modifier': ['screener'],
        'type': ['permanent', 'temporary', 'cast', 'crew'],
        'finaleType': ['series', 'season', 'midseason'],
        'eventType': [
          'artistFolderImported',
          'trackFileRetagged',
          'bookFileRetagged',
          'indexerInfo',
        ],
      };
      for (final MapEntry(key: field, value: values) in words.entries) {
        for (final word in values) {
          expect(FixtureSanitizer().sanitizeJson({field: word}), {field: word});
        }
      }
    });

    test('keeps the general shape of what it replaces', () {
      expect(
        FixtureSanitizer().sanitizeJson([
          'http://nas.invalid/a.JPG',
          'https://nas.invalid/a?token=x',
          'fakeperson@mail.example',
          '/home/fakeperson/a.mkv',
          r'C:\media\a.srt',
          r'\\nas\share',
          'Fake Person',
          'secret.fakeperson',
        ]),
        [
          'http://redacted.invalid/1.jpg',
          'https://redacted.invalid/2',
          'user3@redacted.invalid',
          '/redacted/4.mkv',
          r'C:\redacted\5.srt',
          r'\\redacted.invalid\6',
          'redacted-7',
          'redacted-8',
        ],
      );
    });

    test('gives equal values equal placeholders, across documents', () {
      final sanitizer = FixtureSanitizer();
      expect(sanitizer.sanitizeJson(['a b', 'c d']), [
        'redacted-1',
        'redacted-2',
      ]);
      expect(sanitizer.sanitizeJson('c d'), 'redacted-2');
    });

    test('keeps download ids matching torrent hashes', () {
      final hash = '1234567890' * 3 + 'aabbccddee';
      final sanitizer = FixtureSanitizer();
      final queue =
          sanitizer.sanitizeJson({'downloadId': hash.toUpperCase()})!
              as Map<String, Object?>;
      final torrent =
          sanitizer.sanitizeJson({'hash': hash, 'infohash_v1': hash})!
              as Map<String, Object?>;
      final fake = torrent['hash']! as String;
      expect(fake, isNot(hash));
      expect(fake, matches(r'^[0-9a-f]{40}$'));
      expect(torrent['infohash_v1'], fake);
      expect(queue['downloadId'], fake.toUpperCase());
    });

    test('is stable when run on its own output', () {
      final once = FixtureSanitizer().sanitize(
        jsonEncode({
          'path': '/home/fakeperson/a.mkv',
          'hash': 'f' * 40,
          'a b': 'http://nas.invalid',
          'apiKey': 'FAKE',
        }),
      );
      expect(FixtureSanitizer().sanitize(once), once);
    });

    test('keeps the plain text bodies of qBittorrent', () {
      for (final body in [
        'Ok.',
        'Fails.',
        'Unauthorized',
        'Forbidden',
        'Your IP address has been banned after too many failed authentication '
            'attempts.',
        'v5.1.0',
        'v5.0.0rc1',
        '2.11.4',
      ]) {
        expect(FixtureSanitizer().sanitize('$body\n'), '$body\n');
      }
      expect(FixtureSanitizer().sanitize(''), '');
    });
  });

  group('keeps what contract tests read from', () {
    void unchanged(Object? body) =>
        expect(FixtureSanitizer().sanitizeJson(body), body);

    test('a system status, apart from what describes the server', () {
      const status = {
        'appName': 'Radarr',
        'instanceName': 'Fake Person films',
        'version': '5.27.5.10198',
        'buildTime': '2025-09-01T10:00:00Z',
        'startupPath': '/home/fakeperson/radarr',
        'urlBase': '',
        'osName': 'fakehostname',
        'authentication': 'forms',
        'migrationVersion': 242,
        'runtimeVersion': '8.0.12',
      };
      expect(FixtureSanitizer().sanitizeJson(status), {
        ...status,
        'instanceName': 'redacted-1',
        'startupPath': '/redacted/2',
        'osName': 'redacted-3',
      });
      for (final app in ['Sonarr', 'Lidarr', 'Readarr', 'Prowlarr']) {
        unchanged({'appName': app});
      }
      unchanged({'bazarr_version': '1.5.2', 'sonarr_version': 'unknown'});
    });

    test('add errors', () {
      const error = {
        'propertyName': 'TmdbId',
        'errorMessage': 'This movie has already been added for fakeperson',
        'errorCode': 'MovieExistsValidator',
        'severity': 'error',
      };
      expect(FixtureSanitizer().sanitizeJson([error]), [
        {...error, 'errorMessage': 'redacted-1'},
      ]);
      for (final code in [
        'SeriesExistsValidator',
        'ArtistExistsValidator',
        'AlbumExistsValidator',
        'AuthorExistsValidator',
        'RootFolderAncestorValidator',
        'NotEmptyValidator',
      ]) {
        unchanged({'errorCode': code});
      }
      unchanged({'message': 'invalid csrf token'});
    });

    test('commands', () {
      unchanged({
        'name': 'RefreshSeries',
        'commandName': 'Refresh Series',
        'body': {'name': 'RefreshSeries', 'trigger': 'manual'},
        'status': 'completed',
        'result': 'indeterminate',
        'priority': 'normal',
        'queued': '2024-01-01T00:00:00.1234567Z',
        'duration': '00:00:01.2345678',
      });
      for (final name in ['MissingEpisodeSearch', 'CutoffUnmetBookSearch']) {
        unchanged({'name': name});
      }
    });

    test('queue pages', () {
      unchanged({
        'page': 1,
        'sortKey': 'timeleft',
        'sortDirection': 'ascending',
        'records': [
          {
            'authorId': 3,
            'status': 'warning',
            'trackedDownloadStatus': 'warning',
            'trackedDownloadState': 'importBlocked',
            'protocol': 'usenet',
            'timeleft': '1.02:03:04',
            'quality': {
              'quality': {
                'name': 'WEBDL-1080p',
                'source': 'webdl',
                'resolution': 1080,
              },
            },
            'languages': [
              {'id': 1, 'name': 'English'},
            ],
          },
        ],
      });
      unchanged({'sortKey': 'series.sortTitle'});
      unchanged({'sortKey': 'episodes.airDateUtc'});
    });

    test('history', () {
      unchanged({
        'eventType': 'grabbed',
        'data': {
          'age': '3',
          'ageHours': '72.5083',
          'ageMinutes': '4350.5',
          'size': '1234567890',
          'protocol': '2',
          'publishedDate': '2024-01-01T00:00:00Z',
          'customFormatScore': '-10',
          'tmdbId': '12345',
          'imdbId': '0',
          'releaseSource': 'InteractiveSearch',
          'movieMatchType': 'Title',
          'releaseType': 'SingleEpisode',
          'indexerFlags': 'G_Freeleech, G_Internal',
          'reason': 'MissingFromDisk',
        },
      });
    });

    test('releases and manual import', () {
      unchanged({
        'protocol': 'torrent',
        'indexerFlags': ['G_Freeleech', 'freeleech'],
        'releaseType': 'multiSeasonPack',
        'rejections': <Object?>[],
        'quality': {
          'quality': {'name': 'Bluray-1080p Remux', 'source': 'blurayRaw'},
        },
      });
    });

    test('definitions, health and indexers', () {
      unchanged({
        'quality': {'name': 'FLAC 24bit'},
        'title': 'FLAC 24bit',
      });
      unchanged({'source': 'IndexerVIPExpiredCheck', 'type': 'notice'});
      unchanged({'source': 'RemovedMovieCheck', 'type': 'error'});
      unchanged({
        'privacy': 'semiPrivate',
        'language': 'en-US',
        'categories': [
          {'id': 5040, 'name': 'TV/HD'},
        ],
      });
    });

    test('library details', () {
      unchanged({
        'certification': 'PG-13',
        'minimumAvailability': 'preDB',
        'mediaInfo': {
          'videoCodec': 'x265',
          'videoDynamicRange': 'HDR',
          'videoDynamicRangeType': 'DV HDR10',
          'resolution': '3840x2160',
          'scanType': 'Progressive',
          'audioCodec': 'EAC3 Atmos',
          'audioLanguages': 'eng/jpn',
          'subtitles': 'eng',
        },
      });
      unchanged({
        'audioBitRate': '320 kbps',
        'audioSampleRate': '44.1kHz',
        'audioBits': '16bit',
      });
      unchanged({
        'albumType': 'Album',
        'secondaryTypes': ['Live', 'DJ-mix'],
        'artistType': 'Group',
        'isbn13': '9780000000002',
      });
      unchanged({'status': 'Returning Series'});
    });

    test('Bazarr wanted and history', () {
      unchanged({
        'episode_number': '1x12',
        'year': '2001',
        'timestamp': '3 days ago',
        'parsed_timestamp': '01/02/24 10:11:12',
        'score': '98.33%',
        'action': 1,
        'matches': ['series', 'release_group'],
        'dont_matches': ['hearing_impaired'],
        'language': {'name': 'English', 'code2': 'en', 'code3': 'eng'},
      });
      for (final text in ['now', 'yesterday', 'a minute ago', 'last week']) {
        unchanged({'timestamp': text});
      }
    });
  });

  group('refuses what it cannot parse', () {
    for (final body in [
      '<html><body>fakeperson</body></html>',
      'Set-Cookie: SID=fake',
      '{"apiKey": "FAKE-truncated',
      'fakeperson',
    ]) {
      test(jsonEncode(body), () {
        expect(() => FixtureSanitizer().sanitize(body), _refuses);
      });
    }

    test('a number too large to write back', () {
      expect(() => FixtureSanitizer().sanitize('{"a": 1e999}'), _refuses);
    });

    test('without quoting it', () {
      expect(
        () => FixtureSanitizer().sanitize('{"a": "FAKE-truncated'),
        throwsA(
          isA<UnsanitizableInput>().having(
            (e) => '$e',
            'message',
            isNot(contains('FAKE')),
          ),
        ),
      );
    });
  });

  group('command line', () {
    late Directory directory;
    late StringBuffer errors;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('sanitize');
      errors = StringBuffer();
    });
    tearDown(() => directory.deleteSync(recursive: true));

    File file(String name, [String? content]) {
      final file = File('${directory.path}/$name');
      if (content != null) file.writeAsStringSync(content);
      return file;
    }

    test('writes sanitized files', () async {
      final raw = file('raw', '{"path": "/home/fakeperson"}');
      final out = file('out');
      expect(await run([raw.path, out.path], errors), 0);
      expect(jsonDecode(out.readAsStringSync()), {'path': '/redacted/1'});
    });

    test('writes nothing if any input is refused', () async {
      final good = file('good', '{}');
      final bad = file('bad', '<html>FAKE</html>');
      final out = file('out');
      expect(
        await run([good.path, out.path, bad.path, file('out2').path], errors),
        65,
      );
      expect(out.existsSync(), isFalse);
      expect('$errors', isNot(contains('FAKE')));
    });

    test('writes nothing if an output cannot be a file there', () async {
      final raw = file('raw', '{}');
      final out = file('out');
      for (final bad in [file('missing/out').path, directory.path]) {
        expect(await run([raw.path, out.path, raw.path, bad], errors), 73);
        expect(out.existsSync(), isFalse);
      }
    });

    test('rejects binary and missing inputs', () async {
      final binary = file('binary')..writeAsBytesSync([0xff, 0xfe, 0x00]);
      expect(await run([binary.path, file('out').path], errors), 66);
      expect(await run([file('none').path, file('out').path], errors), 66);
      expect(file('out').existsSync(), isFalse);
    });

    test('explains its usage', () async {
      expect(await run([], errors), 64);
      expect(await run(['only-input'], errors), 64);
    });
  });
}

final Matcher _refuses = throwsA(isA<UnsanitizableInput>());
