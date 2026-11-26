// "Recently added": `CalendarProvider.recentlyAdded()`, the latest import events
// of one page of `GET history`, grouped by item, newest first (FR-024).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overview_support.dart';
import 'support.dart';

/// Pages [records], which are newest first, filtering by `eventType` as the
/// servers do: 3 is the import.
FakeServer _server(List<Object?> records) => FakeServer((request) {
  if (request.path != 'api/v3/history') return const Reply(404, '');
  final filtered = request.query['eventType']?.contains('3') ?? false;
  return page(request, [
    for (final record in records)
      if (!filtered ||
          (record! as JsonObject)['eventType'] == 'downloadFolderImported')
        record,
  ], clamp: false);
});

List<Object?> _recorded(Service service) =>
    service.records('overview_history_imports');

void main() {
  for (final service in services) {
    final first = service == radarr ? 1 : 34;
    final other = service == radarr ? 4 : 35;

    group('${service.name} recently added', () {
      test('asks for the latest imports only', () async {
        final server = _server(_recorded(service));

        await value(service.calendar(server).recentlyAdded());

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/history');
        expect(request.query['page'], ['1']);
        expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
        expect(request.query['sortKey'], ['date']);
        expect(request.query['sortDirection'], ['descending']);
        // A number: the paged history refuses the word. Without the filter a
        // page may hold nothing but grabs.
        expect(request.query['eventType'], contains('3'));
        for (final MapEntry(:key, :value) in service.historyQuery.entries) {
          expect(request.query[key], value);
        }
        expect(request.body, isNull);
      });

      test('lists each item once, with its latest import', () async {
        final records = service.records('overview_history_imports');

        final items = await value(
          service.calendar(_server(records)).recentlyAdded(),
        );

        expect(items.map((item) => item.itemRef), [
          service.itemOf(first),
          service.itemOf(other),
        ]);
        expect(items.map((item) => item.importedAt), [
          DateTime.parse(records[0]['date']! as String),
          DateTime.parse(records[1]['date']! as String),
        ]);
        expect(items.every((item) => item.importedAt.isUtc), isTrue);
        expect(items.map((item) => item.quality?.name), [
          'WEBRip-1080p',
          'Bluray-1080p',
        ]);
        expect(items.map((item) => item.title), [
          service.importTitle(records[0]),
          service.importTitle(records[1]),
        ]);
      });

      test('does not list what is not an import', () async {
        final records = service.records('overview_history_imports');
        records.first['eventType'] = 'grabbed';
        // A server that ignores the filter.
        final server = FakeServer(
          (request) => page(request, records, clamp: false),
        );

        final items = await value(service.calendar(server).recentlyAdded());

        expect(items.map((item) => item.itemRef), [
          service.itemOf(other),
          service.itemOf(first),
        ]);
      });

      test('reads no further page', () async {
        final records = _recorded(service);
        final server = FakeServer(
          (request) => page(request, records, limit: 1, clamp: false),
        );

        final items = await value(service.calendar(server).recentlyAdded());

        expect(server.requests, hasLength(1));
        expect(items, hasLength(1));
      });

      test('is empty on a fresh server', () async {
        final server = _server([]);

        expect(await value(service.calendar(server).recentlyAdded()), isEmpty);
      });

      test('passes a failure on, asking once', () async {
        final server = FakeServer.always(const Reply(500, ''));

        expect(
          await failure(service.calendar(server).recentlyAdded()),
          isA<ServerError>(),
        );
        expect(server.requests, hasLength(1));
      });

      test('cannot understand a page without records', () async {
        final body = service.object('overview_history_imports')
          ..remove('records');
        final server = FakeServer.paths({'history': body});

        expect(
          await failure(service.calendar(server).recentlyAdded()),
          isA<MalformedResponse>(),
        );
      });
    });
  }
}
