// Server options: quality profiles, root folders and tags, read only.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _paths = ['qualityprofile', 'rootfolder', 'tag'];

Map<String, Object?> _bodies(Service service) => {
  for (final path in _paths) path: service.fixture(path),
};

List<(int, String, int?)> _of(
  List<ServerOption> options,
  ServerOptionKind kind,
) => [
  for (final option in options)
    if (option.kind == kind) (option.id, option.label, option.freeSpace),
];

void main() {
  for (final service in services) {
    group('${service.name} options', () {
      test('reads the three lists and nothing else', () async {
        final server = FakeServer.paths(_bodies(service));

        await value(service.client(server).options());

        expect(
          server.requests.map((request) => request.path),
          unorderedEquals([for (final path in _paths) 'api/v3/$path']),
        );
        for (final request in server.requests) {
          expect(request.method, HttpMethod.get);
          expect(request.query, isEmpty);
        }
      });

      test('labels each by name, path or label, in server order', () async {
        final server = FakeServer.paths(_bodies(service));

        final options = await value(service.client(server).options());

        expect(options, hasLength(5));
        expect(_of(options, ServerOptionKind.qualityProfile), [
          (1, 'Any', null),
          (4, 'HD-1080p', null),
        ]);
        expect(_of(options, ServerOptionKind.rootFolder), [
          (1, service == radarr ? '/data/movies' : '/data/tv', 500000000000),
        ]);
        expect(_of(options, ServerOptionKind.tag), [
          (1, 'kids', null),
          (2, '4k', null),
        ]);
      });

      test('accepts a root folder without free space', () async {
        // The server leaves out what it cannot measure.
        final folder = service.list('rootfolder').single..remove('freeSpace');
        final server = FakeServer.paths({
          ..._bodies(service),
          'rootfolder': [folder],
        });

        final options = await value(service.client(server).options());

        expect(_of(options, ServerOptionKind.rootFolder).single.$3, isNull);
      });

      test('is empty where the server has none', () async {
        final server = FakeServer.paths({
          for (final path in _paths) path: <Object?>[],
        });

        expect(await value(service.client(server).options()), isEmpty);
      });

      for (final path in _paths) {
        test('fails as a whole when $path fails', () async {
          final server = FakeServer.paths(_bodies(service)..remove(path));

          expect(
            await failure(service.client(server).options()),
            isA<NotFound>(),
          );
        });

        test('cannot understand a $path entry without an id', () async {
          final entries = service.list(path);
          entries.first.remove('id');
          final server = FakeServer.paths({..._bodies(service), path: entries});

          expect(
            await failure(service.client(server).options()),
            isA<MalformedResponse>(),
          );
        });
      }
    });
  }
}
