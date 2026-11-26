// Wanted: one server page of `GET wanted/missing` or `wanted/cutoff`, monitored
// items only, in the server's order, each mapped by the module.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overview_support.dart';
import 'support.dart';

FakeServer _server(String path, List<Object?> records, {int? limit}) =>
    FakeServer(
      (request) => request.path == 'api/v3/$path'
          ? page(request, records, limit: limit, clamp: false)
          : const Reply(404, ''),
    );

void main() {
  for (final service in services) {
    for (final (name, path, file, read) in [
      (
        'missing',
        'wanted/missing',
        'overview_wanted_missing',
        (Service service, FakeServer server, int? number) => number == null
            ? service.wanted(server).missing()
            : service.wanted(server).missing(page: number),
      ),
      (
        'cutoff unmet',
        'wanted/cutoff',
        'overview_wanted_cutoff',
        (Service service, FakeServer server, int? number) => number == null
            ? service.wanted(server).cutoffUnmet()
            : service.wanted(server).cutoffUnmet(page: number),
      ),
    ]) {
      group('${service.name} $name', () {
        test('asks for the first page of monitored items', () async {
          final server = _server(path, service.records(file));

          await value(read(service, server, null));

          final request = server.requests.single;
          expect(request.method, HttpMethod.get);
          expect(request.path, 'api/v3/$path');
          expect(request.query['page'], ['1']);
          expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
          // The server's default is monitored only.
          expect(request.query['monitored'] ?? ['true'], ['true']);
          for (final MapEntry(:key, :value) in service.itemQuery.entries) {
            expect(request.query[key], value);
          }
          expect(request.body, isNull);
        });

        test('maps the recorded items in server order', () async {
          final result = await value(
            read(service, _server(path, service.records(file)), null),
          );

          expect(result.page, 1);
          expect(result.items.map((item) => item.ref), [
            for (final id
                in name == 'missing'
                    ? (service == radarr ? [2, 3] : [39, 38, 37])
                    : (service == radarr ? [1] : [34]))
              service.itemOf(id),
          ]);
        });

        test('says whether the server has more', () async {
          final server = FakeServer.paths({path: service.fixture(file)});

          final result = await value(read(service, server, null));

          // Sonarr was recorded with 34 missing episodes and three a page.
          expect(result.hasMore, service == sonarr && name == 'missing');
        });

        test('reads the page asked for only', () async {
          final records = [
            ...service.records(file),
            ...service.records(file),
            ...service.records(file),
          ].take(3).toList();
          for (final (number, count, more) in [
            (1, 2, true),
            (2, 1, false),
            (3, 0, false),
          ]) {
            final server = _server(path, records, limit: 2);

            final result = await value(read(service, server, number));

            expect(server.requests.single.query['page'], ['$number']);
            expect(result.page, number);
            expect(result.items, hasLength(count));
            expect(result.hasMore, more);
          }
        });

        test('is empty when nothing is wanted', () async {
          final result = await value(read(service, _server(path, []), null));

          expect(result.items, isEmpty);
          expect(result.hasMore, isFalse);
        });

        test('passes a failure on, asking once', () async {
          final server = FakeServer.always(const Reply(401, ''));

          expect(await failure(read(service, server, null)), isA<AuthFailed>());
          expect(server.requests, hasLength(1));
        });

        for (final field in ['records', 'totalRecords', 'pageSize']) {
          test('cannot understand a page without $field', () async {
            final server = FakeServer.paths({
              path: service.object(file)..remove(field),
            });

            expect(
              await failure(read(service, server, null)),
              isA<MalformedResponse>(),
            );
          });
        }

        test('cannot understand what the mapper cannot', () async {
          final records = service.records(file);
          records.first.remove('title');

          expect(
            await failure(read(service, _server(path, records), null)),
            isA<MalformedResponse>(),
          );
        });
      });
    }
  }
}
