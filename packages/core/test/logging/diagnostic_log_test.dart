import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

// All values are made up. Several contain characters that change when encoded.
const _apiKey = 'seed-api-key value/+1';
const _username = 'seed-user-name';
const _password = 'seed pass&word="x",}';
const _basicUser = 'seed-basic-user';
const _basicPassword = 'seed-basic-pass';
const _cookie = 'SID=seed-session-id; XSRF-TOKEN=seed-xsrf';
const _custom = 'seed-custom-header';

const _credential = Credential(
  apiKey: _apiKey,
  username: _username,
  password: _password,
  basicUser: _basicUser,
  basicPassword: _basicPassword,
  sessionCookie: _cookie,
  customHeaders: {'X-Seed-Gate': _custom},
);

final _basicToken = base64Encode(utf8.encode('$_basicUser:$_basicPassword'));

String _record(DiagnosticLog log, String message, {Object? error}) {
  log.log(LogLevel.error, message, error: error);
  return log.entries.last.toString();
}

final class _Wrapped implements Exception {
  const _Wrapped(this.cause);

  final Object cause;

  @override
  String toString() => 'Wrapped($cause)';
}

final class _Unprintable implements Exception {
  @override
  String toString() => throw StateError('no');
}

void main() {
  group('registered secrets never appear', () {
    final secrets = [
      _apiKey,
      _username,
      _password,
      _basicUser,
      _basicPassword,
      _basicToken,
      _custom,
      'seed-session-id',
      'seed-xsrf',
    ];
    final forms = <String, String Function(String)>{
      'as they are': (s) => s,
      'upper case': (s) => s.toUpperCase(),
      'percent-encoded': Uri.encodeComponent,
      'query-encoded': Uri.encodeQueryComponent,
      'JSON-encoded': jsonEncode,
      'in a URL path': (s) => 'http://host.test/hook/${Uri.encodeFull(s)}/x',
    };

    for (final MapEntry(key: name, value: form) in forms.entries) {
      test(name, () {
        final log = DiagnosticLog()..addCredential(_credential);
        for (final secret in secrets) {
          final written = form(secret);
          log.log(
            LogLevel.error,
            'saw $written here',
            error: _Wrapped([
              {
                'deep': {written},
              },
            ]),
            stackTrace: StackTrace.fromString('#0 f ($written)'),
          );

          expect(
            log.export().toLowerCase(),
            allOf(
              isNot(contains(written.toLowerCase())),
              isNot(contains(secret.toLowerCase())),
            ),
          );
          expect(log.export(), contains(SecretRedactor.marker));
          log.clear();
        }
      });
    }

    test('when two overlap', () {
      final log = DiagnosticLog()..addSecrets(['abcdef', 'defghi']);

      expect(_record(log, '<abcdefghi>'), endsWith('<[redacted]>'));
    });

    test('but a very short value is not registered', () {
      final log = DiagnosticLog()..addSecrets(['', 'a']);

      expect(_record(log, 'a banana'), endsWith('a banana'));
    });
  });

  group('registering late', () {
    // Each entry was stored before its secret was known.
    for (final (name, secret, message) in [
      ('the value itself', _custom, 'got $_custom'),
      ('a value a rule had partly rewritten', 'Seed0ne?&3', 'got Seed0ne?&3'),
      (
        'a value cut off by truncation',
        _custom,
        '${'.' * (DiagnosticLog.maximumTextLength - 6)}$_custom',
      ),
    ]) {
      test('drops an entry holding $name', () {
        final log = DiagnosticLog()
          ..log(LogLevel.info, 'unrelated')
          ..log(LogLevel.info, message)
          ..log(LogLevel.info, 'x', error: message);

        log.addSecrets([secret]);

        expect(log.entries.map((e) => e.message), ['unrelated']);
      });
    }

    test('drops nothing for values already registered', () {
      final log = DiagnosticLog()
        ..addCredential(_credential)
        ..log(LogLevel.info, 'seed');

      log.addCredential(_credential);

      expect(log.entries, hasLength(1));
    });

    test('registers cookie values, not the whole header', () {
      final redactor = SecretRedactor()
        ..addCredential(const Credential(sessionCookie: 'a=seed-1; b=seed-2'));

      final added = redactor.addCredential(
        const Credential(sessionCookie: 'a=seed-1; b=seed-3'),
      );

      expect(added, {'seed-3'});
    });
  });

  group('unregistered secrets are recognised', () {
    // Each line holds `s3cretZ` where a secret would be.
    final lines = <String>[
      'GET http://host.test/api?apikey=s3cretZ',
      'GET https://host.test:8989/sonarr/api?x=1&anything=s3cretZ failed',
      'uri = http://s3cretZ@host.test/api',
      'uri = http://me:s3cretZ@host.test/api',
      'ftp://me:p@s3cretZ@host.test',
      'path api/v3/movie?term=s3cretZ',
      'callback http://host.test/#state=1&other=s3cretZ',
      'Authorization: Bearer s3cretZ',
      'authorization: s3cretZ',
      'Proxy-Authorization: Digest nonce="a", response="s3cretZ"',
      'sent Bearer s3cretZ.abc',
      'sent Basic s3cretZ0Zg== and failed',
      'Cookie: a=1; theme=s3cretZ',
      'Set-Cookie: connect.sid=s3cretZ; Path=/',
      'connect.sid=s3cretZ',
      'QBT_SID_8080=s3cretZ',
      'X-Api-Key: s3cretZ',
      'x-api-key: [s3cretZ]',
      'X-CSRF-Token: s3cretZ',
      'CF-Access-Client-Secret: s3cretZ',
      'api_key=s3cretZ',
      'API key: s3cretZ',
      'passkey = s3cretZ',
      'username=me&password=s3cretZ',
      'password: correct, horse} s3cretZ',
      'password="a b s3cretZ"',
      'password="a"s3cretZ',
      "password: 'unterminated s3cretZ",
      '{"user":"me","password":"a\\"s3cretZ"}',
      r'{\"apiKey\": \"s3cretZ\"}',
      '{"password":\n  "s3cretZ"}',
      '{"headers": {\n  "X-Gate": "s3cretZ"\n}}',
      '{customHeaders: {X-Gate: s3cretZ, X-Other: 1}}',
      '{name: x, nested: [{accessToken: s3cretZ}]}',
      'Credential(basicPassword: s3cretZ)',
      'Invalid HTTP header field value: "s3cretZ\\n"',
      'Invalid argument (password): "s3cretZ"',
      'Invalid argument (apiKey): Must not be empty: "s3cretZ"',
    ];

    for (final line in lines) {
      test(line, () {
        for (final recorded in [
          _record(DiagnosticLog(), line),
          _record(DiagnosticLog(), 'x', error: _Wrapped(line)),
        ]) {
          expect(recorded, isNot(contains('s3cretZ')));
          expect(recorded, contains(SecretRedactor.marker));
        }
      });
    }

    test('a 32-digit hexadecimal key', () {
      const key = '0123456789abcdef0123456789ABCDEF';

      expect(_record(DiagnosticLog(), 'sent $key.'), isNot(contains(key)));
    });

    test('in an ArgumentError', () {
      final recorded = _record(
        DiagnosticLog(),
        'x',
        error: ArgumentError.value('s3cretZ', 'password'),
      );

      expect(recorded, isNot(contains('s3cretZ')));
    });

    // Registered values that are also part of what a rule looks for.
    for (final (registered, line) in [
      ('pass', 'password=s3cretZ'),
      ('https', 'https://me:s3cretZ@host.test/api'),
      ('Bearer', 'sent Bearer s3cretZ.abc'),
      ('word', 'Invalid argument (password): "s3cretZ"'),
    ]) {
      test('although "$registered" is registered', () {
        final log = DiagnosticLog()..addSecrets([registered]);

        final recorded = _record(log, line);

        expect(recorded, isNot(contains('s3cretZ')));
        expect(recorded, isNot(contains(registered)));
      });
    }

    test('in nested collections', () {
      final recorded = _record(
        DiagnosticLog(),
        'x',
        error: {
          'items': [
            {'token': 's3cretZ'},
          ],
          'headers': {'X-Gate': 's3cretZ'},
        },
      );

      expect(recorded, isNot(contains('s3cretZ')));
    });

    test('not in the excerpt of a FormatException', () {
      final recorded = _record(
        DiagnosticLog(),
        'x',
        error: const FormatException('Unexpected character', '<s3cretZ>', 0),
      );

      expect(recorded, isNot(contains('s3cretZ')));
      expect(recorded, contains('Unexpected character'));
    });
  });

  group('keeps what helps find a fault', () {
    for (final line in [
      'GET http://host.test:7878/radarr/api/v3/movie/7 returned 500',
      'HTTP Basic authentication was refused by the proxy',
      'The token or login was rejected. Why? Unknown',
      '#0 read (package:core/src/secrets/secret_store.dart:12:3)',
      'FileSystemException: not found, errno = 2',
    ]) {
      test(line, () {
        expect(_record(DiagnosticLog(), line), endsWith(line));
      });
    }

    test('after a URL query', () {
      expect(
        _record(DiagnosticLog(), 'GET api?apikey=s3cretZ returned 401'),
        endsWith('GET api?[redacted] returned 401'),
      );
    });

    test('around a quoted value', () {
      expect(
        _record(DiagnosticLog(), '{"apiKey": "s3cretZ", "id": 7}'),
        endsWith('{"apiKey": "[redacted]", "id": 7}'),
      );
    });
  });

  group('the log', () {
    test('records time, level, message, cause and stack trace', () {
      final log = DiagnosticLog(clock: () => DateTime.utc(2026, 1, 2, 3));
      log.log(
        LogLevel.warning,
        'slow',
        error: StateError('late'),
        stackTrace: StackTrace.fromString('#0 main'),
      );

      expect(
        log.export(),
        '2026-01-02T03:00:00.000Z warning: slow\n'
        'Bad state: late\n'
        '#0 main',
      );
    });

    test('keeps only the newest entries', () {
      final log = DiagnosticLog(capacity: 2);
      for (final message in ['one', 'two', 'three']) {
        log.log(LogLevel.info, message);
      }

      expect(log.entries.map((e) => e.message), ['two', 'three']);
    });

    test('cuts long texts only after redacting them', () {
      final log = DiagnosticLog()..addSecrets([_custom]);
      final padding = '.' * (DiagnosticLog.maximumTextLength - 4);
      log.log(LogLevel.debug, '$padding$_custom');

      expect(log.entries.single.message, isNot(contains('seed')));
      expect(
        log.entries.single.message.length,
        DiagnosticLog.maximumTextLength + 3,
      );
    });

    test('does not cut a surrogate pair in two', () {
      final padding = '.' * (DiagnosticLog.maximumTextLength - 1);
      final log = DiagnosticLog()..log(LogLevel.debug, '$padding\u{1F600}');

      expect(log.entries.single.message, '$padding...');
    });

    test('removes a value encoded strictly per RFC 3986', () {
      final log = DiagnosticLog()..addSecrets(["seed !'()* value"]);

      expect(
        _record(log, 'at /seed%20%21%27%28%29%2A%20value'),
        endsWith('at /[redacted]'),
      );
    });

    for (final (name, text) in [
      ('a run of #', '#' * 100000),
      ('a run of ?', '?' * 100000),
      ('many quoted values on one line', 'key="v", ' * 20000),
      ('a run of names', 'a:' * 50000),
      ('a run of schemes', 'a://' * 25000),
      ('a run of Bearer', 'Bearer ' * 15000),
    ]) {
      test('redacts $name in reasonable time', () {
        final watch = Stopwatch()..start();

        _record(DiagnosticLog(), text);

        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      });
    }

    for (final (name, text) in [
      ('quoted value', 'password="${'z' * 5000000}"'),
      ('unterminated value', 'password="${r'\z' * 2500000}'),
      ('query', '?${'z' * 5000000}'),
      ('token', 'Bearer ${'Z' * 5000000}'),
    ]) {
      test('does not fail on a huge $name', () {
        final recorded = _record(DiagnosticLog(), text);

        expect(recorded, contains(SecretRedactor.marker));
        expect(recorded.toLowerCase(), isNot(contains('zz')));
        expect(recorded, isNot(contains(r'\z')));
      });
    }

    test('survives an error that cannot describe itself', () {
      expect(
        _record(DiagnosticLog(), 'x', error: _Unprintable()),
        endsWith('Unprintable _Unprintable'),
      );
    });
  });
}
