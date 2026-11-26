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

        expect(options, hasLength(9));
        final profiles = service.list('qualityprofile');
        expect(profiles.first['name'], 'Any');
        expect(_of(options, ServerOptionKind.qualityProfile), [
          for (var id = 1; id <= 6; id++) (id, profiles[id - 1]['name'], null),
        ]);
        expect(_of(options, ServerOptionKind.rootFolder), [
          (
            1,
            service.list('rootfolder').single['path'],
            service == radarr ? 655278714880 : 655361568768,
          ),
        ]);
        // The server lists these two by descending id.
        final tags = service.list('tag');
        expect(_of(options, ServerOptionKind.tag), [
          (2, tags[0]['label'], null),
          (1, tags[1]['label'], null),
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
