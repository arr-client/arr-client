/// Baselines, unreachable servers, summaries, profiles and what is stored with
/// an instance (spec story 12, data-model.md NotificationSubscription and
/// EventMarker).
library;

import 'package:core/core.dart';
import 'package:core/src/storage/database.dart';
import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor, Value;
import 'package:flutter_test/flutter_test.dart';

import '../artwork/support.dart';
import 'support.dart';

const _imported = NotificationEventType.imported;
const _health = NotificationEventType.healthIssue;

/// Once [armed], fails every read of the preferences made after a marker has
/// been written, as a database another connection keeps locked would.
class _LockedAfterMarking extends QueryInterceptor {
  var armed = false;
  var _marked = false;
  var failed = 0;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (armed && statement.contains('event_markers')) _marked = true;
    return executor.runInsert(statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_marked && statement.contains('app_preferences')) {
      failed++;
      throw StateError('locked');
    }
    return executor.runSelect(statement, args);
  }
}

void main() {
  setUpImages();

  late World world;
  late FakeServer server;
  late String id;
  late _LockedAfterMarking database;

  setUp(() async {
    database = _LockedAfterMarking();
    world = await World.start(interceptor: database);
    server = FakeServer('series');
    id = await world.add(server);
  });

  Future<List<String>> check() async => described(await world.check());

  var downloads = 0;

  /// One of each condition, and an event of each kind.
  void happen(String tag) {
    server
      ..imported('import $tag')
      ..failed('failure $tag', downloadId: 'failed-$tag')
      ..download(
        ++downloads,
        'queued $tag',
        QueueSeverity.warning,
        downloadId: 'queued-$tag',
      )
      ..health([('Disk', 'health $tag', HealthLevel.warning)]);
  }

  List<String> noticesOf(String tag) => [
    'imported import $tag',
    'problem failure $tag',
    'problem queued $tag',
    'health health $tag warning',
  ];

  group('subscriptions', () {
    test('are off by default, and nothing is read', () async {
      expect(await world.engine.subscribed(id), isEmpty);
      happen('a');

      expect(await check(), isEmpty);
      expect(server.reads, isEmpty);
    });

    test('are kept per instance and event type', () async {
      final second = await world.add(FakeServer('films'));

      await world.engine.subscribe(world.active(id), _imported);
      await world.engine.subscribe(world.active(id), _health);
      await world.engine.subscribe(world.active(second), _health);

      expect(await world.engine.subscribed(id), {_imported, _health});
      expect(await world.engine.subscribed(second), {_health});

      await world.engine.unsubscribe(id, _health);
      expect(await world.engine.subscribed(id), {_imported});
      expect(await world.engine.subscribed(second), {_health});
    });

    test('limit what is read and notified', () async {
      await world.subscribe(id, [_imported]);
      server.reads.clear();
      happen('a');

      expect(await check(), ['imported import a']);
      expect(server.reads, everyElement(isIn([historyRead, eventsSinceRead])));
    });

    test('are offered by what the instance can do', () async {
      final requests = await world.add(
        FakeServer('requests'),
        serviceType: 'requests',
      );

      expect(world.engine.offered(world.active(id)), {
        _imported,
        NotificationEventType.downloadProblem,
        _health,
      });
      expect(world.engine.offered(world.active(requests)), {
        NotificationEventType.pendingRequest,
        NotificationEventType.ownRequestUpdate,
      });
    });

    test('ignore a type the instance does not offer', () async {
      await world.subscribe(id, [NotificationEventType.pendingRequest]);

      expect(await check(), isEmpty);
    });
  });

  group('the baseline', () {
    test('on subscribing leaves what is there unannounced', () async {
      happen('old');
      await world.subscribe(id);

      expect(await check(), isEmpty);
      happen('new');
      expect(await check(), unorderedEquals(noticesOf('new')));
    });

    test('is taken at once, not at the first check', () async {
      await world.subscribe(id);

      happen('a');

      expect(await check(), unorderedEquals(noticesOf('a')));
    });

    test('of an empty server lets the first events through', () async {
      await world.subscribe(id, [_imported]);
      expect(await check(), isEmpty);

      server.imported('First');

      expect(await check(), ['imported First']);
    });

    test('of a condition lets it notify when it worsens', () async {
      server
        ..download(1, 'Slow', QueueSeverity.warning, downloadId: 'a')
        ..health([('Disk', 'low', HealthLevel.warning)]);
      await world.subscribe(id);

      server
        ..download(1, 'Slow', QueueSeverity.error, downloadId: 'a')
        ..health([('Disk', 'low', HealthLevel.error)]);

      expect(
        await check(),
        unorderedEquals(['problem Slow', 'health low error']),
      );
    });

    test('of one type leaves another where it was', () async {
      await world.subscribe(id, [_imported]);
      server.imported('One');

      await world.engine.subscribe(world.active(id), _health);

      expect(await check(), ['imported One']);
    });

    test('is taken again on subscribing again', () async {
      await world.subscribe(id);
      for (final type in NotificationEventType.values) {
        await world.engine.unsubscribe(id, type);
      }
      happen('off');

      await world.subscribe(id);

      expect(await check(), isEmpty);
    });

    test('waits for the first successful check', () async {
      server.goDown();
      await world.subscribe(id);
      expect(await check(), isEmpty);
      happen('unseen');
      server.comeUp();
      expect(await check(), isEmpty);

      happen('new');

      expect(await check(), unorderedEquals(noticesOf('new')));
    });

    // As after an import of a backup, which stores no markers.
    test('is taken for a stored subscription without a marker', () async {
      happen('old');
      await world.database
          .into(world.database.notificationSubscriptions)
          .insert(
            NotificationSubscriptionsCompanion.insert(
              instanceId: id,
              eventType: _imported.name,
              enabled: const Value(true),
            ),
          );

      expect(await world.engine.subscribed(id), {_imported});
      expect(await check(), isEmpty);
      server.imported('New');
      expect(await check(), ['imported New']);
    });

    test('is taken again when an instance is re-enabled', () async {
      await world.subscribe(id);
      await world.setEnabled(id, false);
      server.reads.clear();
      happen('off');
      expect(await check(), isEmpty);
      expect(server.reads, isEmpty);

      await world.setEnabled(id, true);

      expect(await check(), isEmpty);
      happen('new');
      expect(await check(), unorderedEquals(noticesOf('new')));
    });

    test('of a re-enabled instance that is down waits for it', () async {
      await world.subscribe(id);
      await world.setEnabled(id, false);
      happen('off');
      server.goDown();
      await world.setEnabled(id, true);
      server.comeUp();

      expect(await check(), isEmpty);
      happen('new');
      expect(await check(), unorderedEquals(noticesOf('new')));
    });
  });

  group('an unreachable server', () {
    setUp(() => world.subscribe(id));

    test('raises nothing, and its events come later', () async {
      happen('missed');
      server.goDown();
      expect(await check(), isEmpty);
      expect(await check(), isEmpty);

      server.comeUp();

      expect(await check(), unorderedEquals(noticesOf('missed')));
      expect(await check(), isEmpty);
    });

    test('does not hold up the others', () async {
      final films = FakeServer('films');
      await world.subscribe(await world.add(films), [_imported]);
      server.goDown();
      films.imported('Film');

      expect(await check(), ['imported Film']);
    });

    test('nor does a capability that throws', () async {
      final films = FakeServer('films');
      await world.subscribe(await world.add(films), [_imported]);
      server.throwing.addAll([historyRead, eventsSinceRead, healthRead]);
      films.imported('Film');

      expect(await check(), ['imported Film']);
    });

    test('keeps one failed read from hiding another type', () async {
      server.failing.add(healthRead);
      server.imported('One');

      expect(await check(), ['imported One']);
    });
  });

  group('many events', () {
    setUp(() => world.subscribe(id));

    test('up to five are notified one by one', () async {
      for (var i = 1; i <= 5; i++) {
        server.imported('$i');
      }

      expect(
        await check(),
        unorderedEquals([for (var i = 1; i <= 5; i++) 'imported $i']),
      );
    });

    test('more than five are one summary', () async {
      for (var i = 1; i <= 6; i++) {
        server.imported('$i');
      }

      final notice = (await world.check()).single as SummaryNotice;

      expect(notice.instanceId, id);
      expect(notice.count, 6);
      expect(await check(), isEmpty);
    });

    test('are counted across types', () async {
      happen('a');
      server
        ..imported('b')
        ..imported('c');

      expect(await check(), ['summary 6']);
      expect(await check(), isEmpty);
    });

    test('are counted for each instance by itself', () async {
      final films = FakeServer('films');
      await world.subscribe(await world.add(films), [_imported]);
      for (var i = 1; i <= 3; i++) {
        server.imported('series $i');
        films.imported('film $i');
      }
      expect(await world.check(), hasLength(6));

      for (var i = 4; i <= 9; i++) {
        server.imported('series $i');
      }
      films.imported('film 4');
      final notices = await world.check();

      expect(
        described(notices),
        unorderedEquals(['summary 6', 'imported film 4']),
      );
      expect(notices.whereType<SummaryNotice>().single.instanceId, id);
    });
  });

  test('types of one instance are read at the same time', () async {
    await world.subscribe(id, [_imported, _health]);
    server
      ..hold(historyRead)
      ..hold(healthRead);

    final checking = world.check();
    await server.arrival(healthRead);
    await server.arrival(historyRead);
    server
      ..release(historyRead)
      ..release(healthRead);

    expect(await checking, isEmpty);
  });

  test('a database that fails after the check loses no notice', () async {
    await world.subscribe(id, [_imported]);
    server.imported('One');
    database.armed = true;

    final notices = await world.check();

    expect(database.failed, 1);
    expect(described(notices), ['imported One']);
  });

  group('profiles', () {
    late String away;
    late FakeServer cabin;
    late String cabinId;

    setUp(() async {
      away = await world.profile('Away');
      cabin = FakeServer('cabin');
      cabinId = await world.add(cabin, profileId: away);
      await world.subscribe(id, [_imported]);
      await world.activate(away);
      await world.subscribe(cabinId, [_imported]);
      await world.activate(world.home);
      server.reads.clear();
      cabin.reads.clear();
    });

    test('only the active one is checked', () async {
      server.imported('Home');
      cabin.imported('Cabin');

      expect(await check(), ['imported Home']);
      expect(cabin.reads, isEmpty);
    });

    test('an activated one starts from its current state', () async {
      cabin.imported('While inactive');

      await world.activate(away);

      expect(await check(), isEmpty);
      cabin.imported('Since');
      expect(await check(), ['imported Since']);
    });

    test('also on coming back to it', () async {
      await world.activate(away);
      server.imported('While inactive');

      await world.activate(world.home);

      expect(await check(), isEmpty);
    });

    test('one that is down starts when it first answers', () async {
      cabin.imported('While inactive');
      cabin.goDown();
      await world.activate(away);
      expect(await check(), isEmpty);
      cabin.comeUp();
      expect(await check(), isEmpty);

      cabin.imported('Since');

      expect(await check(), ['imported Since']);
    });

    test('nothing comes of a profile left during its check', () async {
      server
        ..imported('Home')
        ..hold(historyRead)
        ..hold(eventsSinceRead);
      final checking = world.check();
      await Future.any([
        server.arrival(historyRead),
        server.arrival(eventsSinceRead),
      ]);

      await world.registry.switchTo(away);
      server
        ..release(historyRead)
        ..release(eventsSinceRead);

      expect(await checking, isEmpty);
    });

    test('a copy has the subscriptions, and no markers', () async {
      await world.engine.subscribe(world.active(id), _health);
      server.imported('Before the copy');
      final copied = await world.profiles.copyProfile(world.home, name: 'Copy');
      final copy = (copied as Ok<Profile, RuleViolation>).value.id;
      final copyId = (await world.profiles.instances(copy)).single.id;

      expect(await world.engine.subscribed(copyId), {_imported, _health});
      final markers = await world.database
          .select(world.database.eventMarkers)
          .get();
      expect(markers.map((row) => row.instanceId), isNot(contains(copyId)));
      await world.activate(copy);
      expect(await check(), isEmpty);
    });
  });

  group('while a check is under way', () {
    late Future<List<Notice>> checking;

    setUp(() async {
      await world.subscribe(id, [_imported]);
      server
        ..imported('One')
        ..hold(eventsSinceRead)
        ..hold(historyRead);
    });

    Future<void> start() async {
      checking = world.check();
      await Future.any([
        server.arrival(eventsSinceRead),
        server.arrival(historyRead),
      ]);
    }

    void finish() => server
      ..release(eventsSinceRead)
      ..release(historyRead);

    test('a second one does not notify the same again', () async {
      server.reads.clear();
      await start();
      final second = world.check();
      // Both have read the marker before either has an answer.
      while (server.reads.length < 2) {
        await pumpEventQueue();
      }
      finish();

      expect(described([...await checking, ...await second]), ['imported One']);
    });

    test('unsubscribing drops what it finds', () async {
      await start();

      await world.engine.unsubscribe(id, _imported);
      finish();

      expect(await checking, isEmpty);
      expect(
        await world.database.select(world.database.eventMarkers).get(),
        isEmpty,
      );
    });

    // As the app does from its own isolate, which this check does not hear of.
    test('a switch saved by another isolate drops what it finds', () async {
      final away = await world.profile('Away');
      await start();

      await world.preferences.setActiveProfile(away);
      finish();

      expect(await checking, isEmpty);
    });
  });

  group('deleting', () {
    Future<Set<String>> subscribers() async => {
      for (final row
          in await world.database
              .select(world.database.notificationSubscriptions)
              .get())
        row.instanceId,
    };

    Future<Set<String>> marked() async => {
      for (final row
          in await world.database.select(world.database.eventMarkers).get())
        row.instanceId,
    };

    test('an instance deletes its subscriptions and markers', () async {
      final kept = await world.add(FakeServer('films'));
      await world.subscribe(id);
      await world.subscribe(kept, [_imported]);
      expect(await subscribers(), {id, kept});
      expect(await marked(), {id, kept});

      await world.profiles.deleteInstance(id);

      expect(await subscribers(), {kept});
      expect(await marked(), {kept});
      expect(await world.engine.subscribed(id), isEmpty);
    });

    test('a profile deletes those of its instances', () async {
      final away = await world.profile('Away');
      final cabinId = await world.add(FakeServer('cabin'), profileId: away);
      await world.activate(away);
      await world.subscribe(cabinId);
      expect(await marked(), {cabinId});

      await world.profiles.deleteProfile(away);

      expect(await subscribers(), isEmpty);
      expect(await marked(), isEmpty);
    });

    test('an instance during its check does not fail the check', () async {
      final films = FakeServer('films');
      await world.subscribe(await world.add(films), [_imported]);
      await world.subscribe(id, [_health]);
      films.imported('Film');
      server
        ..health([('Disk', 'low', HealthLevel.warning)])
        ..hold(healthRead);
      final checking = world.check();
      await server.arrival(healthRead);

      await world.profiles.deleteInstance(id);
      await world.registry.refresh();
      server.release(healthRead);

      expect(described(await checking), ['imported Film']);
    });
  });
}
