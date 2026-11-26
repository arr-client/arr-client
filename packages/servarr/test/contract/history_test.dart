// The history read: one page of `GET history`, newest first.
//
// `eventType` words of the family map to `HistoryEventType`; `details` holds the
// text values of `data` under the server's keys. Events since a time, item
// history and mark-failed come with later tasks.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

FakeServer _server(List<Object?> records, {int? limit}) => FakeServer(
  (request) => request.path == 'api/v3/history'
      ? page(request, records, limit: limit, clamp: false)
      : const Reply(404, ''),
);

Future<HistoryEvent> _one(
  Service service, [
  Map<String, Object?> changes = const {},
  List<String> without = const [],
]) async {
  final record = service.records('history').first
    ..addAll(changes)
    ..removeWhere((key, _) => without.contains(key));
  final result = await value(service.client(_server([record])).history());
  return result.items.single;
}

void main() {
  for (final service in services) {
    group('${service.name} history', () {
      test('asks for the first page, newest first', () async {
        final server = _server(service.records('history'));

        await value(service.client(server).history());

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/history');
        expect(request.query['page'], ['1']);
        expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
        expect(request.query['sortKey'], ['date']);
        expect(request.query['sortDirection'], ['descending']);
        expect(request.body, isNull);
      });

      test('maps the events in server order', () async {
        final result = await value(
          service.client(_server(service.records('history'))).history(),
        );

        expect(result.page, 1);
        expect(result.hasMore, isFalse);
        expect(result.items.map((event) => event.id), [
          for (final record in service.records('history')) record['id'],
        ]);
        expect(result.items.map((event) => event.eventType), [
          HistoryEventType.imported,
          HistoryEventType.grabbed,
          HistoryEventType.deleted,
        ]);
      });

      test('maps an event', () async {
        final event = await _one(service);

        expect(event.date, DateTime.utc(2026, 11, 20, 10, 15));
        expect(event.date.isUtc, isTrue);
        expect(event.sourceTitle, contains('1080p'));
        expect(event.downloadId, 'ABCDEF0000000000000000000000000000000001');
        expect(
          event.itemRef,
          ItemRef(
            instanceId: instanceId,
            kind: service == radarr ? MediaKind.movie : MediaKind.episode,
            remoteId: service == radarr ? 11 : 301,
          ),
        );
        expect(event.details['releaseGroup'], 'GRP');
        expect(event.details['downloadClientName'], 'qBittorrent');
      });

      test('leaves out a detail without a value', () async {
        final result = await value(
          service.client(_server(service.records('history'))).history(),
        );

        // The grab has `"nzbInfoUrl": null`.
        expect(result.items[1].details, isNot(contains('nzbInfoUrl')));
        expect(result.items[1].details['indexer'], 'Example Indexer');
      });

      test('accepts an event without a download or details', () async {
        final event = await _one(service, const {}, ['downloadId', 'data']);

        expect(event.downloadId, isNull);
        expect(event.details, isEmpty);
      });

      final types = {
        'grabbed': HistoryEventType.grabbed,
        'downloadFolderImported': HistoryEventType.imported,
        'downloadFailed': HistoryEventType.failed,
        'downloadIgnored': HistoryEventType.other,
        'unknown': HistoryEventType.other,
        'someFutureEvent': HistoryEventType.other,
        if (service == radarr) ...{
          'movieFolderImported': HistoryEventType.imported,
          'movieFileRenamed': HistoryEventType.renamed,
          'movieFileDeleted': HistoryEventType.deleted,
        } else ...{
          'seriesFolderImported': HistoryEventType.imported,
          'episodeFileRenamed': HistoryEventType.renamed,
          'episodeFileDeleted': HistoryEventType.deleted,
        },
      };
      for (final MapEntry(key: word, value: type) in types.entries) {
        test('reads event type $word', () async {
          expect((await _one(service, {'eventType': word})).eventType, type);
        });
      }

      for (final field in ['id', 'date']) {
        test('cannot understand an event without $field', () async {
          final records = service.records('history');
          records[1].remove(field);

          expect(
            await failure(service.client(_server(records)).history()),
            isA<MalformedResponse>(),
          );
        });
      }

      test('cannot understand a date that is not one', () async {
        final records = service.records('history');
        records[0]['date'] = 'yesterday';

        expect(
          await failure(service.client(_server(records)).history()),
          isA<MalformedResponse>(),
        );
      });
    });

    group('${service.name} history paging', () {
      // Three events, two a page.
      for (final (number, ids, more) in [
        (1, 2, true),
        (2, 1, false),
        (3, 0, false),
      ]) {
        test('reads page $number only', () async {
          final server = _server(service.records('history'), limit: 2);

          final result = await value(
            service.client(server).history(page: number),
          );

          expect(server.requests.single.query['page'], ['$number']);
          expect(result.page, number);
          expect(result.items, hasLength(ids));
          expect(result.hasMore, more);
        });
      }

      test('has no further page when the last one is full', () async {
        final records = service.records('history').sublist(0, 2);

        final result = await value(
          service.client(_server(records, limit: 2)).history(),
        );

        expect(result.items, hasLength(2));
        expect(result.hasMore, isFalse);
      });

      for (final field in ['records', 'totalRecords']) {
        test('cannot understand a page without $field', () async {
          final body = service.object('history')..remove(field);
          final server = FakeServer.paths({'history': body});

          expect(
            await failure(service.client(server).history()),
            isA<MalformedResponse>(),
          );
        });
      }
    });
  }
}
