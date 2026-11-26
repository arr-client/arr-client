// Sending a result to a download client (story 11 scenario 2): the server's
// acceptance or refusal.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A server and a release it found, with nothing sent since.
Future<(Harness, Release)> _found([int index = 0]) async {
  final harness = Harness();
  final release = (await succeed(harness.indexers.search('a')))[index];
  harness.server.requests.clear();
  return (harness, release);
}

void main() {
  test('names the release by its guid and indexer alone', () async {
    for (var index = 0; index < 3; index++) {
      final wire = records(fixture('search'))[index];
      final (harness, release) = await _found(index);

      await succeed(harness.indexers.grab(release));

      final request = harness.server.requests.single;
      expect(asked(request), 'POST search');
      expect(request.query, isEmpty);
      expect(sentBody(request), {
        'guid': wire['guid'],
        'indexerId': wire['indexerId'],
      });
    }
  });

  for (final (failure, status, recording) in const [
    // The server forgets what it found after 30 minutes.
    (NotFound(), 404, 'grab_expired'),
    (Conflict(), 409, 'grab_indexer_failed'),
    (ServerError(statusCode: 500), 500, 'grab_no_client'),
    (Validation(['invalid']), 400, 'grab_invalid'),
  ]) {
    test('passes on the refusal $status and sends once', () async {
      final (harness, release) = await _found();
      harness.server.routes['POST search'] = failedAnswer(
        failure,
        status: status,
        body: jsonEncode(fixture(recording)),
      );

      expect(await failureOf(harness.indexers.grab(release)), same(failure));
      expect(harness.server.sent, ['POST search']);
    });
  }

  for (final failure in <ServiceFailure>[
    const Unreachable(),
    const AuthFailed(),
    const OutcomeUnknown(),
  ]) {
    test('passes on ${failure.runtimeType} and sends once', () async {
      final (harness, release) = await _found();
      harness.server.routes['POST search'] = failedAnswer(failure);

      expect(await failureOf(harness.indexers.grab(release)), same(failure));
      expect(harness.server.sent, ['POST search']);
    });
  }

  // The server accepted the request, so it may well be downloading.
  for (final body in ['{"guid":', '[]', '']) {
    test('cannot tell the outcome of the answer "$body"', () async {
      final (harness, release) = await _found();
      harness.server.routes['POST search'] = textAnswer(body);

      expect(
        await failureOf(harness.indexers.grab(release)),
        isA<OutcomeUnknown>(),
      );
      expect(harness.server.sent, ['POST search']);
    });
  }
}
