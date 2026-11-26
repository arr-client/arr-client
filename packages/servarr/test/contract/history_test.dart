// The history read: one page of `GET history`, newest first.
//
// `eventType` words of the family map to `HistoryEventType`; `details` holds the
// text values of `data` under the server's keys, but none that may hold a secret:
// a grab records the indexer's addresses, which carry its API key. Events since a
// time, item history and mark-failed come with later tasks.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

FakeServer _server(List<Object?> records, {int? limit}) => FakeServer(
  (request) => request.path == 'api/v3/history'
      ? page(request, records, limit: limit, clamp: false)
      : const Reply(404, ''),
);

/// The recorded record with [id].
Map<String, Object?> _recorded(Service service, int id) =>
    service.records('history').singleWhere((record) => record['id'] == id);

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
        expect(result.items.map((event) => event.id), [5, 4, 3, 2, 1]);
        expect(result.items.map((event) => event.eventType), [
          HistoryEventType.failed,
          HistoryEventType.deleted,
          HistoryEventType.imported,
          HistoryEventType.grabbed,
          HistoryEventType.grabbed,
        ]);
      });

      test('maps an event', () async {
        final record = _recorded(service, 1);
        final data = record['data']! as JsonObject;

        final event = await _one(service, record);

        expect(
          event.date,
          DateTime.utc(
            2026,
            11,
            26,
            13,
            service == radarr ? 23 : 24,
            service == radarr ? 59 : 4,
          ),
        );
        expect(event.date.isUtc, isTrue);
        expect(event.sourceTitle, record['sourceTitle']);
        expect(
          event.downloadId,
          'ABCDEF000000000000000000000000000000000'
          '${service == radarr ? 2 : 5}',
        );
        expect(
          event.itemRef,
          ItemRef(
            instanceId: instanceId,
            kind: service == radarr ? MediaKind.movie : MediaKind.episode,
            remoteId: service == radarr ? 1 : 13,
          ),
        );
        expect(event.details['releaseGroup'], data['releaseGroup']);
        expect(event.details['downloadClientName'], data['downloadClientName']);
        expect(event.details['protocol'], '2');
      });

      test('keeps no address of a recorded grab', () async {
        final record = _recorded(service, 1);
        final data = record['data']! as JsonObject;
        const addresses = ['downloadUrl', 'nzbInfoUrl', 'guid'];
        expect(data.keys, containsAll(addresses));

        final event = await _one(service, record);

        expect(
          event.details.keys,
          unorderedEquals([
            for (final MapEntry(:key, :value) in data.entries)
              if (value != null && !addresses.contains(key)) key,
          ]),
        );
      });

      test('leaves out a detail without a value', () async {
        // The import by hand has `"downloadClient": null`.
        final event = await _one(service, _recorded(service, 3));

        expect(event.eventType, HistoryEventType.imported);
        expect(event.details, isNot(contains('downloadClient')));
        expect(event.details['fileId'], '1');
      });

      test('accepts an event without a download or details', () async {
        final event = await _one(service, const {}, ['downloadId', 'data']);

        expect(event.downloadId, isNull);
        expect(event.details, isEmpty);
      });

      test('keeps no address or secret among the details', () async {
        // All made up.
        const key = 'not-a-real-key';
        final event = await _one(service, {
          'data': {
            'indexer': 'Example Indexer',
            'releaseGroup': 'GRP',
            // Addresses, whatever they are called.
            'link': 'http://indexer.invalid/download/$key/file.torrent',
            'source': 'magnet:?xt=urn:btih:0000&tr=$key',
            'redirect': 'indexer.invalid/get?u=https%3A%2F%2Fx.invalid%2F$key',
            'message': 'Failed to get https://indexer.invalid/$key/1',
            'query': '/api?apikey=$key',
            'note': 'apikey=$key',
            // Names for secrets and addresses, whatever they hold.
            'downloadUrl': key,
            'nzbInfoUrl': key,
            'guid': key,
            'apiKey': key,
            'pass_key': key,
            'authToken': key,
            'password': key,
            'Cookie': key,
            'Authorization': key,
            // A value that is only a key in shape.
            'other': '0123456789abcdef0123456789abcdef',
          },
        });

        expect(event.details, {
          'indexer': 'Example Indexer',
          'releaseGroup': 'GRP',
        });
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
          final records = service.records('history').sublist(0, 3);
          final server = _server(records, limit: 2);

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

      test('is empty on a fresh server', () async {
        final server = FakeServer.paths({
          'history': service.fixture('history_empty'),
        });

        final result = await value(service.client(server).history());

        expect(result.items, isEmpty);
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
