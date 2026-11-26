// The failures of the activity reads and writes. A write is sent once, whatever
// happens, and an unknown outcome is reported as such (constitution; FR-073).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servarr/servarr.dart';

import 'activity_support.dart';
import 'support.dart';

typedef _Call = ServiceResult<Object?> Function(ServarrClient client);

const _candidate = ManualImportCandidate(
  path: '/redacted/1.mkv',
  size: 1,
  downloadId: 'ABCDEF01',
  rawJson: {'id': 1, 'path': '/redacted/1.mkv'},
);

const _options = RemoveOptions(removeFromClient: true, blocklist: true);

final _writes = <String, _Call>{
  'remove': (client) => client.remove(7, _options),
  'removeMany': (client) => client.removeMany([7, 8], _options),
  'grabNow': (client) => client.grabNow(7),
  'markFailed': (client) => client.markFailed(3),
  'unblock one': (client) => client.unblock([4]),
  'unblock several': (client) => client.unblock([4, 2]),
  'reprocess': (client) =>
      client.reprocess([_candidate], mapping: mapping(radarr)),
  'importFiles': (client) =>
      client.importFiles([_candidate], mapping: mapping(radarr)),
};

final _reads = <String, _Call>{
  'eventsSince': (client) => client.eventsSince(DateTime.utc(2026)),
  'blocklist': (client) => client.blocklist(),
  'importCandidates': (client) =>
      client.importCandidates(waiting(), mapping: mapping(radarr)),
  'importChoices': (client) => client.importChoices(),
};

final _failures = <String, (Answer, Matcher)>{
  'an unreachable server': (const NoReply(Unreachable()), isA<Unreachable>()),
  'a rejected key': (const Reply(401, ''), isA<AuthFailed>()),
  'a refusal': (const Reply(403, ''), isA<Forbidden>()),
  'something gone': (const Reply(404, ''), isA<NotFound>()),
  'a conflict': (const Reply(409, ''), isA<Conflict>()),
  'rejected values': (const Reply(400, '[]'), isA<Validation>()),
  'a server error': (
    Reply.json({'message': 'Example'}, status: 500),
    isA<ServerError>(),
  ),
  'a login page': (
    const Reply(
      200,
      '<!doctype html><title>Sign in</title>',
      type: 'text/html',
    ),
    isA<ProxyInterception>(),
  ),
};

void main() {
  for (final MapEntry(key: name, value: write) in _writes.entries) {
    group(name, () {
      final failures = {
        ..._failures,
        'an unknown outcome': (
          const NoReply(OutcomeUnknown()),
          isA<OutcomeUnknown>(),
        ),
      };
      for (final MapEntry(key: cause, value: (answer, expected))
          in failures.entries) {
        test('reports $cause and is sent once', () async {
          final server = FakeServer.always(answer);

          expect(await failure(write(radarr.client(server))), expected);

          expect(server.requests, hasLength(1));
          expect(server.requests.single.method, isNot(HttpMethod.get));
        });
      }
    });
  }

  group('every activity read', () {
    final failures = {
      ..._failures,
      'JSON that breaks off': (
        const Reply(200, '[{"id":'),
        isA<MalformedResponse>(),
      ),
      'JSON of another shape': (
        const Reply(200, '"ok"'),
        isA<MalformedResponse>(),
      ),
    };

    for (final MapEntry(key: name, value: read) in _reads.entries) {
      for (final MapEntry(key: cause, value: (answer, expected))
          in failures.entries) {
        test('$name reports $cause', () async {
          final server = FakeServer.always(answer);

          expect(await failure(read(radarr.client(server))), expected);

          // No path is asked for twice.
          final paths = server.requests.map((request) => request.path);
          expect(paths.toSet(), hasLength(paths.length));
        });
      }
    }
  });
}
