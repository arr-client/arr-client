// Queue states and history events that the activity recording produced, for
// what the first reads (queue_test.dart, history_test.dart) had only written by
// hand.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<List<QueueItem>> _queue(Service service, String fixture) => value(
  service.client(FakeServer.paths({'queue': service.fixture(fixture)})).queue(),
);

Map<String, Object?> _record(
  Service service,
  String fixture,
  bool Function(Map<String, Object?> record) test,
) => service.records(fixture).firstWhere(test);

Future<QueueItem> _item(
  Service service,
  String fixture,
  bool Function(Map<String, Object?> record) test,
) async {
  final id = _record(service, fixture, test)['id'];
  return (await _queue(service, fixture)).singleWhere((item) => item.id == id);
}

void main() {
  for (final service in services) {
    group('${service.name} recorded queue states', () {
      test('paused', () async {
        final item = await _item(
          service,
          'queue_states',
          (record) => record['status'] == 'paused',
        );

        expect(item.status, QueueStatus.paused);
        expect(item.severity, QueueSeverity.ok);
      });

      test('queued', () async {
        final item = await _item(
          service,
          'queue_activity',
          (record) => record['status'] == 'queued',
        );

        expect(item.status, QueueStatus.queued);
        expect(item.eta, isNull);
      });

      test('a warning with only the download client error', () async {
        bool test(Map<String, Object?> record) => record['status'] == 'warning';
        final record = _record(service, 'queue_states', test);

        final item = await _item(service, 'queue_states', test);

        expect(item.status, QueueStatus.warning);
        expect(item.severity, QueueSeverity.ok);
        expect(item.messages, [record['errorMessage']]);
      });

      test('a delayed usenet release', () async {
        final item = await _item(
          service,
          'queue_activity',
          (record) =>
              record['status'] == 'delay' && record['protocol'] == 'usenet',
        );

        expect(item.status, QueueStatus.delayed);
        expect(item.protocol, DownloadProtocol.usenet);
        expect(item.downloadId, isNull);
      });

      test('import pending', () async {
        final item = await _item(
          service,
          'queue_activity',
          (record) => record['trackedDownloadState'] == 'importPending',
        );

        expect(item.trackedState, TrackedState.importPending);
        expect(item.needsManualImport, isTrue);
      });

      test('a status message without messages', () async {
        // The first of three has a title alone.
        bool test(Map<String, Object?> record) =>
            (record['statusMessages'] as List<Object?>?)?.length == 3;
        final entries =
            (_record(service, 'queue_activity', test)['statusMessages']!
                    as List<Object?>)
                .cast<JsonObject>();
        expect(entries.first['messages'], isEmpty);

        final item = await _item(service, 'queue_activity', test);

        expect(item.messages, [
          entries.first['title'],
          for (final entry in entries.skip(1))
            ...entry['messages']! as List<Object?>,
        ]);
      });

      // Asked for page 99 of 10 entries, 3 a page, the server answered with
      // page 3, as `page` of support.dart does.
      test('past its end answers an earlier page', () {
        final recorded = service.object('queue_past_end');

        final reply = page(
          ServiceRequest(
            HttpMethod.get,
            'api/v3/queue',
            query: const {
              'page': ['99'],
              'pageSize': ['3'],
            },
          ),
          List.filled(recorded['totalRecords']! as int, 0),
        );

        expect(recorded['page'], 3);
        expect(reply.body, contains('"page":3,'));
      });
    });

    group('${service.name} recorded history events', () {
      test('maps renames, deletions and ignored downloads', () async {
        final server = FakeServer.paths({
          'history': service.fixture('history_activity'),
        });

        final events = (await value(service.client(server).history())).items;

        final types = {
          for (final record in service.records('history_activity'))
            record['eventType']! as String: events
                .singleWhere((event) => event.id == record['id'])
                .eventType,
        };
        expect(types, {
          'grabbed': HistoryEventType.grabbed,
          'downloadFolderImported': HistoryEventType.imported,
          'downloadFailed': HistoryEventType.failed,
          'downloadIgnored': HistoryEventType.other,
          if (service == radarr) ...{
            'movieFileRenamed': HistoryEventType.renamed,
            'movieFileDeleted': HistoryEventType.deleted,
          } else ...{
            'episodeFileRenamed': HistoryEventType.renamed,
            'episodeFileDeleted': HistoryEventType.deleted,
          },
        });
      });
    });
  }
}
