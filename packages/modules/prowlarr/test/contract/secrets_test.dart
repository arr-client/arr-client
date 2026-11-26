// Search results hold the indexers' addresses with their passkeys, and
// Prowlarr's own API key in its download addresses (see support.dart). None of
// it may be logged or persisted (FR-065, FR-070), and no key goes into the
// address of a request, which servers and proxies log.
//
// The only places a secret may go are the results kept in memory and the guid
// in the body of the grab.

import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _passkey = 'PASSKEY0123456789abcdef';
const _apiKey = 'APIKEY0123456789abcdef';
final _secret = RegExp('$_passkey|$_apiKey');

/// The recorded results, with addresses shaped as the server's.
List<Map<String, Object?>> _results() => [
  for (final (index, record) in records(fixture('search')).indexed)
    {
      ...record,
      'guid': 'https://tracker.test/dl/$index?passkey=$_passkey',
      'infoUrl': 'https://tracker.test/details/$index?passkey=$_passkey',
      'commentUrl': 'https://tracker.test/c/$index?passkey=$_passkey',
      'posterUrl': 'https://tracker.test/p/$index?passkey=$_passkey',
      'downloadUrl':
          'http://server.test/${record['indexerId']}/download'
          '?apikey=$_apiKey&link=x',
      'magnetUrl': 'magnet:?xt=urn:btih:0&tr=https%3A%2F%2Ft%2F$_passkey',
    },
];

/// Runs [body] and gives all it printed.
Future<List<String>> _printed(Future<void> Function() body) async {
  final lines = <String>[];
  final before = debugPrint;
  debugPrint = (message, {wrapWidth}) => lines.add('$message');
  try {
    await runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );
  } finally {
    debugPrint = before;
  }
  return lines;
}

/// All of a failure that could reach a screen or a log.
String _described(ServiceFailure failure) => switch (failure) {
  Validation(:final messages) => '$failure $messages',
  _ => '$failure',
};

/// Nothing was logged, printed or stored that holds a secret.
void _expectKept(Harness harness, List<String> printed) {
  expect(harness.logger.lines.where(_secret.hasMatch), isEmpty);
  expect(printed.where(_secret.hasMatch), isEmpty);
  // Results are not cached at all: the cache is a database on the device.
  expect(harness.cache.used, isEmpty);
  for (final request in harness.server.requests) {
    expect('${request.path} ${request.query}', isNot(matches(_secret)));
    expect('${request.headers}', isNot(matches(_secret)));
  }
}

void main() {
  test('a search and a grab leave no trace of a key', () async {
    final harness = Harness()
      ..server.routes['GET search'] = jsonAnswer(_results())
      // The answer repeats the guid.
      ..server.routes['POST search'] = jsonAnswer({
        'guid': _results().first['guid'],
        'indexerId': 1,
      });

    final printed = await _printed(() async {
      final found = await succeed(harness.indexers.search('a'));
      expect(found, hasLength(3));
      await succeed(harness.indexers.grab(found.first));
    });

    _expectKept(harness, printed);
    // The guid is what the server knows the release by; nothing else goes
    // back.
    expect(sentBody(harness.server.requests.last), {
      'guid': _results().first['guid'],
      'indexerId': 1,
    });
  });

  group('failures say nothing of a key', () {
    final broken = <String, String>{
      'results that break off': jsonEncode(_results()).substring(0, 900),
      'a result without its indexer': jsonEncode([
        _results().first..remove('indexerId'),
      ]),
      'a result with a size that is not a number': jsonEncode([
        {..._results().first, 'size': _results().first['downloadUrl']},
        <String, Object?>{},
      ]),
    };
    for (final MapEntry(key: name, value: body) in broken.entries) {
      test('for $name', () async {
        final harness = Harness()
          ..server.routes['GET search'] = textAnswer(body);

        final printed = await _printed(() async {
          final failure = await failureOf(harness.indexers.search('a'));
          expect(_described(failure), isNot(matches(_secret)));
        });

        _expectKept(harness, printed);
      });
    }

    // An error page of the server may quote the address that failed.
    for (final (failure, status) in const [
      (NotFound(), 404),
      (Conflict(), 409),
      (ServerError(statusCode: 500), 500),
    ]) {
      test('for a grab refused with $status', () async {
        final harness = Harness()
          ..server.routes['GET search'] = jsonAnswer(_results())
          ..server.routes['POST search'] = failedAnswer(
            failure,
            status: status,
            body: jsonEncode({
              'message': 'failed ${_results().first['guid']}',
              'description': 'at ${_results().first['downloadUrl']}',
            }),
          );

        final printed = await _printed(() async {
          final found = await succeed(harness.indexers.search('a'));
          final refused = await failureOf(harness.indexers.grab(found.first));
          expect(_described(refused), isNot(matches(_secret)));
        });

        _expectKept(harness, printed);
      });
    }

    test('for a grab with an answer that breaks off', () async {
      final harness = Harness()
        ..server.routes['GET search'] = jsonAnswer(_results())
        ..server.routes['POST search'] = textAnswer(
          '{"guid":"${_results().first['guid']}',
        );

      final printed = await _printed(() async {
        final found = await succeed(harness.indexers.search('a'));
        expect(
          await failureOf(harness.indexers.grab(found.first)),
          isA<OutcomeUnknown>(),
        );
      });

      _expectKept(harness, printed);
    });
  });

  // An indexer's settings hold its address and credentials.
  test('reading the indexers leaves no trace of their settings', () async {
    final wire = records(fixture('indexer'));
    for (final record in wire) {
      record['indexerUrls'] = ['https://tracker.test/$_passkey/'];
      record['fields'] = [
        {'name': 'passkey', 'value': _passkey},
      ];
    }
    final harness = Harness()..server.routes['GET indexer'] = jsonAnswer(wire);

    final printed = await _printed(() async {
      await succeed(harness.indexers.indexers());
      await succeed(harness.indexers.categories());
    });

    _expectKept(harness, printed);
  });
}
