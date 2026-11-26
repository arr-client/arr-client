// The blocklist: one page of `GET blocklist`, newest first, and the removal of
// entries.
//
// Mapping of a record to `BlocklistEntry`:
//   id, date, sourceTitle  as sent, the date in UTC
//   itemRef   `refs.item`, else `refs.parent`: a Sonarr entry names its series
//             and a list of episodes, but no one episode
//   quality   quality.quality id and name
//   reason    message
//
// One entry is removed with `DELETE blocklist/{id}`, several with
// `DELETE blocklist/bulk`.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_support.dart';
import 'support.dart';

FakeServer _server(List<Object?> records, {int? limit}) => FakeServer(
  (request) => request.path == 'api/v3/blocklist'
      ? page(request, records, limit: limit, clamp: false)
      : const Reply(404, ''),
);

Future<BlocklistEntry> _one(
  Service service, [
  Map<String, Object?> changes = const {},
  List<String> without = const [],
]) async {
  final record = service.records('blocklist').first
    ..addAll(changes)
    ..removeWhere((key, _) => without.contains(key));
  final result = await value(service.client(_server([record])).blocklist());
  return result.items.single;
}

void main() {
  for (final service in services) {
    group('${service.name} blocklist', () {
      test('asks for the first page, newest first', () async {
        final server = _server(service.records('blocklist'));

        await value(service.client(server).blocklist());

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/blocklist');
        expect(request.query.keys.toSet(), {
          'page',
          'pageSize',
          'sortKey',
          'sortDirection',
        });
        expect(request.query['page'], ['1']);
        expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
        expect(request.query['sortKey'], ['date']);
        expect(request.query['sortDirection'], ['descending']);
        expect(request.body, isNull);
      });

      test('keeps the server order', () async {
        final result = await value(
          service.client(_server(service.records('blocklist'))).blocklist(),
        );

        expect(result.page, 1);
        expect(result.hasMore, isFalse);
        expect(result.items.map((entry) => entry.id), [4, 3, 2, 1]);
      });

      test('maps an entry', () async {
        final record = service.records('blocklist').first;

        final entry = await _one(service);

        expect(entry.id, 4);
        expect(entry.sourceTitle, record['sourceTitle']);
        expect(entry.date, DateTime.utc(2026, 11, 26, 13, 58, 15));
        expect(entry.date.isUtc, isTrue);
        expect(entry.reason, record['message']);
        expect(entry.reason, isNotEmpty);
        expect(entry.quality?.id, service == radarr ? 7 : 3);
        expect(
          entry.quality?.name,
          service == radarr ? 'Bluray-1080p' : 'WEBDL-1080p',
        );
        expect(
          entry.itemRef,
          service == radarr
              ? itemRef(MediaKind.movie, 10)
              : itemRef(MediaKind.series, 1),
        );
      });

      test('accepts an entry with only what it cannot do without', () async {
        final entry = await _one(service, const {}, [
          'quality',
          'message',
          'movieId',
          'seriesId',
          'movie',
          'series',
        ]);

        expect(entry.quality, isNull);
        expect(entry.reason, isNull);
        expect(entry.itemRef, isNull);
      });

      for (final field in ['id', 'date']) {
        test('cannot understand an entry without $field', () async {
          final records = service.records('blocklist');
          records[1].remove(field);

          expect(
            await failure(service.client(_server(records)).blocklist()),
            isA<MalformedResponse>(),
          );
        });
      }

      // Four entries, three a page.
      for (final (number, count, more) in [(1, 3, true), (2, 1, false)]) {
        test('reads page $number only', () async {
          final server = _server(service.records('blocklist'), limit: 3);

          final result = await value(
            service.client(server).blocklist(page: number),
          );

          expect(server.requests.single.query['page'], ['$number']);
          expect(result.page, number);
          expect(result.items, hasLength(count));
          expect(result.hasMore, more);
        });
      }

      test('is empty on a fresh server', () async {
        final server = FakeServer.paths({
          'blocklist': service.fixture('blocklist_empty'),
        });

        final result = await value(service.client(server).blocklist());

        expect(result.items, isEmpty);
        expect(result.hasMore, isFalse);
      });
    });

    group('${service.name} blocklist removal', () {
      test('removes one entry', () async {
        // A single removal answers with no body, even for an entry that is
        // already gone.
        final server = only('blocklist/4', const Reply(200, ''));

        await value(service.client(server).unblock([4]));

        final request = server.requests.single;
        expect(request.method, HttpMethod.delete);
        expect(request.path, 'api/v3/blocklist/4');
        expect(request.query, isEmpty);
        expect(request.body, isNull);
      });

      test('removes several entries at once', () async {
        final server = only('blocklist/bulk', const Reply(200, '{}'));

        await value(service.client(server).unblock([4, 2]));

        final request = server.requests.single;
        expect(request.method, HttpMethod.delete);
        expect(request.path, 'api/v3/blocklist/bulk');
        expect(request.query, isEmpty);
        expect((request.body! as JsonBody).value, {
          'ids': [4, 2],
        });
      });

      test('asks nothing to remove nothing', () async {
        final server = only('blocklist/bulk', const Reply(200, '{}'));

        await value(service.client(server).unblock([]));

        expect(server.requests, isEmpty);
      });
    });
  }
}
