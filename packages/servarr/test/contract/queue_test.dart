// The queue read: every page of `GET queue`, downloads the server cannot match
// included.
//
// Mapping of a record to `QueueItem`:
//   id, title, downloadId, downloadClient  as sent
//   itemRef, parent      from `refs`
//   status               the word; 'delay' is `delayed`
//   trackedState         trackedDownloadState; `unknown` when left out
//   severity             trackedDownloadStatus; `ok` when left out
//   messages             errorMessage, and of each statusMessages entry its
//                        messages, or its title when it has none
//   progress, sizeLeft   QueueItem.progressFrom(size, sizeleft), sizeleft
//   eta                  timeleft, '[d.]hh:mm:ss[.fffffff]'
//   quality              quality.quality id and name
//   protocol             'torrent', 'usenet'
//   needsManualImport    status 'completed' with trackedDownloadStatus
//                        'warning', as the services' web UI decides it

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _hash = 'ABCDEF0000000000000000000000000000000001';

FakeServer _server(List<Object?> records, {int? limit}) => FakeServer(
  (request) => request.path == 'api/v3/queue'
      ? page(request, records, limit: limit)
      : const Reply(404, ''),
);

Future<List<QueueItem>> _read(Service service, List<Object?> records) =>
    value(service.client(_server(records)).queue());

/// The first record of the fixture, downloading, with [changes].
Future<QueueItem> _one(
  Service service, [
  Map<String, Object?> changes = const {},
  List<String> without = const [],
]) async {
  final record = service.records('queue').first
    ..addAll(changes)
    ..removeWhere((key, _) => without.contains(key));
  return (await _read(service, [record])).single;
}

/// [count] downloads with ids from 1.
List<Object?> _many(Service service, int count) => [
  for (var id = 1; id <= count; id++)
    {...service.records('queue').first, 'id': id},
];

void main() {
  for (final service in services) {
    group('${service.name} queue', () {
      test('asks for downloads the server cannot match', () async {
        final server = _server(service.records('queue'));

        await value(service.client(server).queue());

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/queue');
        expect(request.query[service.includeUnknown], ['true']);
        expect(request.query['page'], ['1']);
        expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
        expect(request.body, isNull);
      });

      test('keeps the server order', () async {
        final items = await _read(service, service.records('queue'));

        expect(items.map((item) => item.id), [
          for (final record in service.records('queue')) record['id'],
        ]);
      });

      test('maps a download in progress', () async {
        final item = (await _read(service, service.records('queue'))).first;

        expect(item.title, contains('1080p'));
        expect(item.status, QueueStatus.downloading);
        expect(item.trackedState, TrackedState.downloading);
        expect(item.severity, QueueSeverity.ok);
        expect(item.messages, isEmpty);
        expect(item.progress, 0.75);
        expect(item.sizeLeft, service == radarr ? 2000000000 : 500000000);
        expect(item.eta, const Duration(minutes: 45, seconds: 30));
        expect(item.downloadId, _hash);
        expect(item.downloadClient, 'qBittorrent');
        expect(item.protocol, DownloadProtocol.torrent);
        expect(item.quality?.id, service == radarr ? 7 : 3);
        expect(
          item.quality?.name,
          service == radarr ? 'Bluray-1080p' : 'WEBDL-1080p',
        );
        expect(item.needsManualImport, isFalse);
      });

      test('refers to the item and its parent', () async {
        final item = (await _read(service, service.records('queue'))).first;

        if (service == radarr) {
          expect(
            item.itemRef,
            const ItemRef(
              instanceId: instanceId,
              kind: MediaKind.movie,
              remoteId: 11,
            ),
          );
          expect(item.parent, isNull);
        } else {
          expect(
            item.itemRef,
            const ItemRef(
              instanceId: instanceId,
              kind: MediaKind.episode,
              remoteId: 301,
            ),
          );
          expect(
            item.parent,
            const ItemRef(
              instanceId: instanceId,
              kind: MediaKind.series,
              remoteId: 21,
            ),
          );
        }
      });

      test('keeps a download the server cannot match', () async {
        final item = (await _read(service, service.records('queue')))[1];

        expect(item.itemRef, isNull);
        expect(item.parent, isNull);
        expect(item.title, 'Some.Unmatched.Release-GRP');
        expect(item.status, QueueStatus.completed);
        expect(item.trackedState, TrackedState.importPending);
        expect(item.severity, QueueSeverity.warning);
        expect(item.needsManualImport, isTrue);
        expect(item.progress, 1);
        expect(item.sizeLeft, 0);
        expect(
          item.messages,
          unorderedEquals([
            service == radarr
                ? 'Unable to parse movie title from the file name'
                : 'Unable to parse the series from the file name',
            'No files found are eligible for import',
          ]),
        );
      });

      test('maps a delayed release that has no download yet', () async {
        final item = (await _read(service, service.records('queue')))[2];

        expect(item.status, QueueStatus.delayed);
        expect(item.trackedState, TrackedState.unknown);
        expect(item.severity, QueueSeverity.ok);
        expect(item.downloadId, isNull);
        expect(item.downloadClient, isNull);
        expect(item.protocol, DownloadProtocol.usenet);
        expect(item.progress, 0);
        expect(
          item.eta,
          const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
        );
        expect(item.needsManualImport, isFalse);
      });

      final statuses = {
        'unknown': QueueStatus.unknown,
        'queued': QueueStatus.queued,
        'paused': QueueStatus.paused,
        'downloading': QueueStatus.downloading,
        'completed': QueueStatus.completed,
        'failed': QueueStatus.failed,
        'warning': QueueStatus.warning,
        'delay': QueueStatus.delayed,
        'downloadClientUnavailable': QueueStatus.downloadClientUnavailable,
        'fallback': QueueStatus.fallback,
        'someFutureStatus': QueueStatus.unknown,
      };
      for (final MapEntry(key: word, value: status) in statuses.entries) {
        test('reads status $word', () async {
          expect((await _one(service, {'status': word})).status, status);
        });
      }

      final states = {
        'downloading': TrackedState.downloading,
        'importPending': TrackedState.importPending,
        'importBlocked': TrackedState.importBlocked,
        'importing': TrackedState.importing,
        'imported': TrackedState.imported,
        'failedPending': TrackedState.failedPending,
        'failed': TrackedState.failed,
        'ignored': TrackedState.ignored,
        'someFutureState': TrackedState.unknown,
      };
      for (final MapEntry(key: word, value: state) in states.entries) {
        test('reads tracked state $word', () async {
          final item = await _one(service, {'trackedDownloadState': word});

          expect(item.trackedState, state);
        });
      }

      final severities = {
        'ok': QueueSeverity.ok,
        'warning': QueueSeverity.warning,
        'error': QueueSeverity.error,
        'someFutureSeverity': QueueSeverity.unknown,
      };
      for (final MapEntry(key: word, value: severity) in severities.entries) {
        test('reads severity $word', () async {
          final item = await _one(service, {'trackedDownloadStatus': word});

          expect(item.severity, severity);
        });
      }

      for (final (status, tracked, needed) in [
        ('completed', 'warning', true),
        ('completed', 'ok', false),
        ('completed', 'error', false),
        ('downloading', 'warning', false),
      ]) {
        test('$status with $tracked needs manual import: $needed', () async {
          final item = await _one(service, {
            'status': status,
            'trackedDownloadStatus': tracked,
          });

          expect(item.needsManualImport, needed);
        });
      }

      test('shows the error of the download client', () async {
        final item = await _one(service, {
          'status': 'warning',
          'trackedDownloadStatus': 'warning',
          'errorMessage': 'The download is stalled with no connections',
        });

        expect(item.messages, ['The download is stalled with no connections']);
      });

      test('reads a protocol it does not know as unknown', () async {
        final item = await _one(service, {'protocol': 'someFutureProtocol'});

        expect(item.protocol, DownloadProtocol.unknown);
      });

      test('accepts a record with only what is always sent', () async {
        final item = await _one(service, const {}, [
          'quality',
          'timeleft',
          'estimatedCompletionTime',
          'downloadId',
          'downloadClient',
          'statusMessages',
          'trackedDownloadStatus',
          'trackedDownloadState',
        ]);

        expect(item.quality, isNull);
        expect(item.eta, isNull);
        expect(item.messages, isEmpty);
      });

      test('has no progress while the size is not known', () async {
        final item = await _one(service, {'size': 0, 'sizeleft': 0});

        expect(item.progress, 0);
      });

      test('ignores fields it does not know', () async {
        final item = await _one(service, {
          'someFutureField': {'a': 1},
        });

        expect(item.status, QueueStatus.downloading);
      });

      test('cannot understand a record without an id', () async {
        final records = service.records('queue');
        records[1].remove('id');

        expect(
          await failure(service.client(_server(records)).queue()),
          isA<MalformedResponse>(),
        );
      });

      test('is empty when nothing is queued', () async {
        final server = _server(const []);

        expect(await value(service.client(server).queue()), isEmpty);
        expect(server.requests, hasLength(1));
      });
    });

    group('${service.name} queue paging', () {
      for (final count in [4, 5]) {
        test('reads every page of $count downloads', () async {
          final server = _server(_many(service, count), limit: 2);

          final items = await value(service.client(server).queue());

          expect(items.map((item) => item.id), [
            for (var id = 1; id <= count; id++) id,
          ]);
          expect(
            [for (final request in server.requests) request.query['page']],
            [
              for (var number = 1; number <= (count + 1) ~/ 2; number++)
                ['$number'],
            ],
          );
          for (final request in server.requests) {
            expect(request.query[service.includeUnknown], ['true']);
            expect(
              request.query['pageSize'],
              server.requests.first.query['pageSize'],
            );
          }
        });
      }

      test('reads a long queue completely', () async {
        final server = _server(_many(service, 1234));

        final items = await value(service.client(server).queue());

        expect(items.map((item) => item.id).toSet(), hasLength(1234));
        expect(items, hasLength(1234));
      });

      test('lists each download once when the queue shrinks', () async {
        var records = _many(service, 3);
        // The third finishes after the first page was read, so the server
        // answers the second request with page 1 again.
        final server = FakeServer((request) {
          final reply = page(request, records, limit: 2);
          records = records.sublist(0, 2);
          return reply;
        });

        final items = await value(service.client(server).queue());

        expect(items.map((item) => item.id), [1, 2]);
        expect(server.requests, hasLength(2));
      });

      // A server or proxy that ignores the page number, with a total that
      // would never be reached.
      test('stops when the server repeats a page', () async {
        final records = _many(service, 2);
        final server = FakeServer(
          (_) => Reply.json({
            'page': 1,
            'pageSize': 2,
            'totalRecords': 1000000,
            'records': records,
          }),
        );

        final items = await value(service.client(server).queue());

        expect(items.map((item) => item.id), [1, 2]);
        expect(server.requests, hasLength(2));
      });

      test('gives no partial queue when a later page fails', () async {
        final records = _many(service, 3);
        final server = FakeServer(
          (request) => request.query['page']!.single == '1'
              ? page(request, records, limit: 2)
              : const NoReply(Unreachable()),
        );

        expect(
          await failure(service.client(server).queue()),
          isA<Unreachable>(),
        );
        expect(server.requests, hasLength(2));
      });
    });
  }
}
