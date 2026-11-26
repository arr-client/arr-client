// Contract of the shared Servarr client: system status here, and the failures
// common to all its reads. The other reads have their own files.
//
// The API these tests expect of `package:servarr/servarr.dart` (T037). The
// records are those of `package:core`.
//
//   /// What a queue or history record is about, as the module reads its ids.
//   typedef ServarrRefs = ({ItemRef? item, ItemRef? parent});
//
//   typedef ServarrStatus = ({String appName, String version});
//
//   final class ServarrClient {
//     ServarrClient(
//       ServiceHttpClient http, {
//       required String apiPath,                  // 'api/v3'
//       required String includeUnknownParameter,  // 'includeUnknownMovieItems'
//       required ServarrRefs Function(JsonObject record) refs,
//     });
//
//     ServiceResult<ServarrStatus> status();           // GET system/status
//     ServiceResult<List<ServerOption>> options();     // qualityprofile,
//                                                      // rootfolder, tag
//     ServiceResult<List<QueueItem>> queue();          // GET queue, all pages
//     ServiceResult<ResultPage<HistoryEvent>> history({int page = 1});
//     ServiceResult<Command> commandStatus(int commandId);
//     ServiceResult<List<HealthIssue>> health();
//   }
//
// Rules for all of them:
// - A failure of `http.send` is returned as its `ServiceFailure`, unchanged.
//   Nothing is retried; the core client already retries reads.
// - A body that is not JSON of the expected shape, or a record without its id,
//   is `MalformedResponse`. Nothing throws.
// - Unknown fields are ignored and unknown enum words map to `unknown` (history:
//   `other`).
// - `refs` is given each queue and history record as decoded.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servarr/servarr.dart';

import 'support.dart';

typedef _Read = ServiceResult<Object?> Function(ServarrClient client);

final _reads = <String, _Read>{
  'status': (client) => client.status(),
  'options': (client) => client.options(),
  'queue': (client) => client.queue(),
  'history': (client) => client.history(),
  'commandStatus': (client) => client.commandStatus(77),
  'health': (client) => client.health(),
};

void main() {
  for (final service in services) {
    group('${service.name} system status', () {
      test('reads the application name and version', () async {
        final server = FakeServer.paths({
          'system/status': service.fixture('system_status'),
        });

        final status = await value(service.client(server).status());

        expect(status.appName, service.name);
        expect(status.version, service.version);
        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/system/status');
        expect(request.query, isEmpty);
        expect(request.body, isNull);
      });

      for (final field in ['appName', 'version']) {
        test('cannot understand a status without $field', () async {
          final body = service.object('system_status')..remove(field);
          final server = FakeServer.paths({'system/status': body});

          expect(
            await failure(service.client(server).status()),
            isA<MalformedResponse>(),
          );
        });
      }
    });
  }

  group('every read', () {
    final failures = <String, (Answer, Matcher)>{
      'an unreachable server': (
        const NoReply(Unreachable()),
        isA<Unreachable>(),
      ),
      'a rejected key': (const Reply(401, ''), isA<AuthFailed>()),
      'a server error': (
        Reply.json({'message': 'Example'}, status: 500),
        isA<ServerError>().having((f) => f.statusCode, 'statusCode', 500),
      ),
      'a login page': (
        const Reply(
          200,
          '<!doctype html><title>Sign in</title>',
          type: 'text/html',
        ),
        isA<ProxyInterception>(),
      ),
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
