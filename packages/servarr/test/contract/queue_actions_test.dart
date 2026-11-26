// The queue's writes: `DELETE queue/{id}`, `DELETE queue/bulk` and
// `POST queue/grab/{id}`.
//
// `removeFromClient` and `blocklist` are always stated, as the server removes
// from the download client unless told not to. `skipRedownload` is the opposite
// of `searchReplacement` and is sent only with `blocklist=true`, where alone it
// matters.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_support.dart';
import 'support.dart';

/// Each choice the user has, and the query that states it.
const _choices = [
  (
    RemoveOptions(removeFromClient: true, blocklist: false),
    {
      'removeFromClient': ['true'],
      'blocklist': ['false'],
    },
  ),
  (
    RemoveOptions(
      removeFromClient: false,
      blocklist: false,
      searchReplacement: true,
    ),
    {
      'removeFromClient': ['false'],
      'blocklist': ['false'],
    },
  ),
  (
    RemoveOptions(removeFromClient: true, blocklist: true),
    {
      'removeFromClient': ['true'],
      'blocklist': ['true'],
      'skipRedownload': ['true'],
    },
  ),
  (
    RemoveOptions(
      removeFromClient: false,
      blocklist: true,
      searchReplacement: true,
    ),
    {
      'removeFromClient': ['false'],
      'blocklist': ['true'],
      'skipRedownload': ['false'],
    },
  ),
];

String _name(RemoveOptions options) =>
    'client ${options.removeFromClient}, blocklist ${options.blocklist}, '
    'search ${options.searchReplacement}';

void main() {
  for (final service in services) {
    group('${service.name} queue removal', () {
      for (final (options, query) in _choices) {
        test('removes one with ${_name(options)}', () async {
          // A single removal answers with no body.
          final server = only('queue/7', const Reply(200, ''));

          await value(service.client(server).remove(7, options));

          final request = server.requests.single;
          expect(request.method, HttpMethod.delete);
          expect(request.path, 'api/v3/queue/7');
          expect(request.query, query);
          expect(request.body, isNull);
        });

        test('removes several with ${_name(options)}', () async {
          final server = only('queue/bulk', const Reply(200, '{}'));

          await value(service.client(server).removeMany([7, 9, 8], options));

          final request = server.requests.single;
          expect(request.method, HttpMethod.delete);
          expect(request.path, 'api/v3/queue/bulk');
          expect(request.query, query);
          expect((request.body! as JsonBody).value, {
            'ids': [7, 9, 8],
          });
        });
      }

      test('asks nothing to remove nothing', () async {
        final server = only('queue/bulk', const Reply(200, '{}'));

        await value(
          service
              .client(server)
              .removeMany(
                [],
                const RemoveOptions(removeFromClient: true, blocklist: false),
              ),
        );

        expect(server.requests, isEmpty);
      });

      test('reports an entry that is gone', () async {
        // As recorded.
        final server = only(
          'queue/7',
          Reply.json({'message': 'NotFound'}, status: 404),
        );

        expect(
          await failure(
            service
                .client(server)
                .remove(
                  7,
                  const RemoveOptions(removeFromClient: true, blocklist: false),
                ),
          ),
          isA<NotFound>(),
        );
        expect(server.requests, hasLength(1));
      });
    });

    group('${service.name} grab now', () {
      test('grabs the delayed entry', () async {
        final server = only('queue/grab/401329872', const Reply(200, '{}'));

        await value(service.client(server).grabNow(401329872));

        final request = server.requests.single;
        expect(request.method, HttpMethod.post);
        expect(request.path, 'api/v3/queue/grab/401329872');
        expect(request.query, isEmpty);
        expect(request.body, isNull);
      });

      test('reports a release the server could not download', () async {
        // As recorded where the indexer no longer had it; the server's message
        // goes no further.
        final server = only(
          'queue/grab/7',
          Reply.json({'message': 'Downloading torrent failed'}, status: 500),
        );

        expect(
          await failure(service.client(server).grabNow(7)),
          isA<ServerError>(),
        );
        expect(server.requests, hasLength(1));
      });
    });
  }
}
