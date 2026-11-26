/// What each event type notifies of, once (spec story 12, data-model.md
/// EventMarker).
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../artwork/support.dart';
import 'support.dart';

void main() {
  setUpImages();

  late World world;
  late FakeServer server;
  late String id;

  setUp(() async {
    world = await World.start();
    server = FakeServer('series');
    id = await world.add(server);
  });

  Future<List<String>> check() async => described(await world.check());

  group('imported', () {
    setUp(() => world.subscribe(id, [NotificationEventType.imported]));

    test('notifies each import once', () async {
      final event = server.imported('One');

      final notices = await world.check();

      expect(described(notices), ['imported One']);
      final notice = notices.single as ImportedNotice;
      expect(notice.instanceId, id);
      expect(notice.event.id, event.id);
      expect(notice.event.itemRef, event.itemRef);
      expect(await check(), isEmpty);
      server.imported('Two');
      expect(await check(), ['imported Two']);
    });

    test('notifies an import of the same second as the last seen', () async {
      server.imported('One');
      expect(await check(), ['imported One']);

      server.imported('Two', sameSecond: true);

      expect(await check(), ['imported Two']);
      expect(await check(), isEmpty);
    });

    test('ignores other kinds of history event', () async {
      for (final type in HistoryEventType.values) {
        if (type != HistoryEventType.imported) server.record(type, type.name);
      }

      expect(await check(), isEmpty);
    });
  });

  group('download problems', () {
    setUp(() => world.subscribe(id, [NotificationEventType.downloadProblem]));

    test('are queue entries with a warning or an error', () async {
      server
        ..download(1, 'Fine', QueueSeverity.ok, downloadId: 'a')
        ..download(2, 'Odd', QueueSeverity.unknown, downloadId: 'b')
        ..download(3, 'Warned', QueueSeverity.warning, downloadId: 'c')
        ..download(4, 'Broken', QueueSeverity.error, downloadId: 'd')
        ..download(5, 'Unnamed', QueueSeverity.error);

      expect(
        await check(),
        unorderedEquals([
          'problem Warned',
          'problem Broken',
          'problem Unnamed',
        ]),
      );
      expect(await check(), isEmpty);
    });

    test('are failures in the history', () async {
      server.failed('Gone', downloadId: 'a');

      final notice = (await world.check()).single as DownloadProblemNotice;

      expect(notice.instanceId, id);
      expect(notice.title, 'Gone');
      expect(notice.downloadId, 'a');
      expect(notice.itemRef, server.events.single.itemRef);
      expect(await check(), isEmpty);
    });

    test('notify one failure once from queue and history together', () async {
      server
        ..download(1, 'Broken', QueueSeverity.error, downloadId: 'a')
        ..failed('Broken', downloadId: 'a');

      expect(await check(), ['problem Broken']);
      expect(await check(), isEmpty);
    });

    test('do not repeat a queue failure when the history has it', () async {
      server.download(1, 'Broken', QueueSeverity.error, downloadId: 'a');
      expect(await check(), ['problem Broken']);

      server.failed('Broken', downloadId: 'a');

      expect(await check(), isEmpty);
    });

    test('do not repeat it when it has left the queue by then', () async {
      server.download(1, 'Broken', QueueSeverity.error, downloadId: 'a');
      expect(await check(), ['problem Broken']);

      server.queue.clear();
      server.failed('Broken', downloadId: 'a');

      expect(await check(), isEmpty);
    });

    test('do not repeat a history failure the queue shows later', () async {
      server.failed('Broken', downloadId: 'a');
      expect(await check(), ['problem Broken']);

      server.download(1, 'Broken', QueueSeverity.error, downloadId: 'a');

      expect(await check(), isEmpty);
    });

    test('notify a download that fails again long after', () async {
      server.failed('Broken', downloadId: 'a');
      expect(await check(), ['problem Broken']);
      expect(await check(), isEmpty);
      expect(await check(), isEmpty);

      server.failed('Broken', downloadId: 'a');

      expect(await check(), ['problem Broken']);
    });

    test('count the entries of one download once', () async {
      server
        ..download(1, 'Pack', QueueSeverity.warning, downloadId: 'a')
        ..download(2, 'Pack', QueueSeverity.warning, downloadId: 'a');

      expect(await check(), ['problem Pack']);
    });

    test('notify again when a warning becomes an error', () async {
      server.download(1, 'Slow', QueueSeverity.warning, downloadId: 'a');
      expect(await check(), ['problem Slow']);

      server.download(1, 'Slow', QueueSeverity.error, downloadId: 'a');

      expect(await check(), ['problem Slow']);
      server.download(1, 'Slow', QueueSeverity.warning, downloadId: 'a');
      expect(await check(), isEmpty);
    });

    test('notify again after the condition cleared', () async {
      server.download(1, 'Slow', QueueSeverity.warning, downloadId: 'a');
      expect(await check(), ['problem Slow']);
      server.download(1, 'Slow', QueueSeverity.ok, downloadId: 'a');
      expect(await check(), isEmpty);

      server.download(1, 'Slow', QueueSeverity.warning, downloadId: 'a');

      expect(await check(), ['problem Slow']);
    });

    test('are not cleared by a queue that could not be read', () async {
      server.download(1, 'Slow', QueueSeverity.warning, downloadId: 'a');
      expect(await check(), ['problem Slow']);
      server.failing.add(queueRead);
      expect(await check(), isEmpty);

      server.comeUp();

      expect(await check(), isEmpty);
    });
  });

  group('health', () {
    setUp(() => world.subscribe(id, [NotificationEventType.healthIssue]));

    test('notifies a new warning or error once', () async {
      server.health([
        ('Disk', 'low', HealthLevel.warning),
        ('Indexer', 'down', HealthLevel.error),
      ]);

      final notices = await world.check();

      expect(
        described(notices),
        unorderedEquals(['health low warning', 'health down error']),
      );
      expect(notices.map((notice) => notice.instanceId), [id, id]);
      expect(await check(), isEmpty);
    });

    test('ignores notices and levels the app does not know', () async {
      server.health([
        ('Update', 'available', HealthLevel.notice),
        ('Odd', 'strange', HealthLevel.unknown),
      ]);

      expect(await check(), isEmpty);
    });

    test('tells problems apart by source and message', () async {
      server.health([('Disk', 'low', HealthLevel.warning)]);
      await world.check();

      server.health([
        ('Disk', 'low', HealthLevel.warning),
        ('Disk', 'failing', HealthLevel.warning),
        ('Cache', 'low', HealthLevel.warning),
      ]);

      expect(
        await check(),
        unorderedEquals(['health failing warning', 'health low warning']),
      );
    });

    test('notifies each time a warning worsens to an error', () async {
      server.health([('Disk', 'low', HealthLevel.warning)]);
      expect(await check(), ['health low warning']);
      server.health([('Disk', 'low', HealthLevel.error)]);
      expect(await check(), ['health low error']);
      expect(await check(), isEmpty);

      server.health([('Disk', 'low', HealthLevel.warning)]);
      expect(await check(), isEmpty);

      server.health([('Disk', 'low', HealthLevel.error)]);
      expect(await check(), ['health low error']);
    });

    test('notifies again after the problem cleared', () async {
      server.health([('Disk', 'low', HealthLevel.warning)]);
      expect(await check(), ['health low warning']);
      server.health([]);
      expect(await check(), isEmpty);

      server.health([('Disk', 'low', HealthLevel.warning)]);

      expect(await check(), ['health low warning']);
    });

    test('is not cleared by a read that failed', () async {
      server.health([('Disk', 'low', HealthLevel.warning)]);
      expect(await check(), ['health low warning']);
      server.failing.add(healthRead);
      expect(await check(), isEmpty);

      server.comeUp();

      expect(await check(), isEmpty);
    });
  });

  group('requests', () {
    late FakeServer requests;
    late String requestsId;

    setUp(() async {
      requests = FakeServer('requests');
      requestsId = await world.add(requests, serviceType: 'requests');
    });

    group('pending', () {
      setUp(() async {
        requests.request(1);
        await world.subscribe(requestsId, [
          NotificationEventType.pendingRequest,
        ]);
      });

      test('notifies a new pending request once', () async {
        expect(await check(), isEmpty);
        requests.request(2);

        final notice = (await world.check()).single as PendingRequestNotice;

        expect(notice.instanceId, requestsId);
        expect(notice.request.id, 2);
        expect(await check(), isEmpty);
      });

      test('ignores a new request that is not pending', () async {
        requests
          ..request(2, status: RequestStatus.approved)
          ..request(3, status: RequestStatus.declined);

        expect(await check(), isEmpty);
      });

      test('keeps what it knew when the list cannot be read', () async {
        requests.failing.add(requestsRead);
        expect(await check(), isEmpty);
        requests.comeUp();
        requests.request(2);

        expect(await check(), ['pending 2']);
      });
    });

    group('of the user', () {
      Future<void> subscribe() =>
          world.subscribe(requestsId, [NotificationEventType.ownRequestUpdate]);

      for (final status in [RequestStatus.approved, RequestStatus.declined]) {
        test('notify once when ${status.name}', () async {
          requests.request(1, by: me);
          await subscribe();
          requests.request(1, by: me, status: status);

          final notice = (await world.check()).single as OwnRequestNotice;

          expect(notice.instanceId, requestsId);
          expect(notice.request.status, status);
          expect(await check(), isEmpty);
        });
      }

      test('notify when partly available and when available', () async {
        requests.request(1, by: me, status: RequestStatus.approved);
        await subscribe();
        requests.request(
          1,
          by: me,
          status: RequestStatus.approved,
          availability: Availability.processing,
        );
        expect(await check(), isEmpty);
        requests.request(
          1,
          by: me,
          status: RequestStatus.approved,
          availability: Availability.partial,
        );
        expect(await check(), ['own 1 approved partial']);

        requests.request(
          1,
          by: me,
          status: RequestStatus.completed,
          availability: Availability.available,
        );

        expect(await check(), ['own 1 completed available']);
        expect(await check(), isEmpty);
      });

      test('notify once when approved and available at once', () async {
        requests.request(1, by: me);
        await subscribe();

        requests.request(
          1,
          by: me,
          status: RequestStatus.approved,
          availability: Availability.available,
        );

        expect(await check(), ['own 1 approved available']);
      });

      test('say nothing of what was so already', () async {
        requests.request(
          1,
          by: me,
          status: RequestStatus.approved,
          availability: Availability.available,
        );
        await subscribe();

        expect(await check(), isEmpty);
      });

      test('say nothing of requests of others', () async {
        requests.request(1);
        await subscribe();

        requests.request(
          1,
          status: RequestStatus.approved,
          availability: Availability.available,
        );

        expect(await check(), isEmpty);
      });

      test('are found on later pages of the list', () async {
        requests
          ..requestPageSize = 2
          ..request(1, by: me)
          ..request(2)
          ..request(3);
        await subscribe();

        requests.request(1, by: me, status: RequestStatus.approved);

        expect(await check(), ['own 1 approved unknown']);
      });

      test('wait while the user cannot be told apart', () async {
        requests.request(1, by: me);
        await subscribe();
        requests.request(1, by: me, status: RequestStatus.approved);
        requests.failing.add(sessionRead);
        // An engine may keep the user's id, and then needs no session.
        final meanwhile = await check();

        requests.comeUp();

        expect([...meanwhile, ...await check()], ['own 1 approved unknown']);
      });
    });
  });
}
