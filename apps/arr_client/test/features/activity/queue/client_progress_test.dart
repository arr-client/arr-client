/// The download client's figures in the queue (spec story 7).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/fake_library.dart';
import '../../../app/support.dart';
import 'support.dart';

const interval = Duration(seconds: 4);

void main() {
  late QueueModule module;
  late ProgressModule clients;
  late TestApp app;
  late FakeQueue films;
  late FakeProgress client;

  /// The app with the queue of "Films" and the download client "Seedbox", and
  /// more clients if named, not yet on screen.
  Future<void> start(
    WidgetTester tester, {
    List<String> others = const [],
    Size size = const Size(400, 800),
    QueueModule? queues,
  }) async {
    useScreen(tester, size);
    module = queues ?? QueueModule();
    clients = ProgressModule();
    films = module.of('Films');
    client = clients.of('Seedbox');
    app = await TestApp.start(tester, modules: [module, clients]);
    await app.add(module, 'Films');
    for (final name in ['Seedbox', ...others]) {
      await app.add(clients, name);
    }
  }

  Future<void> open(WidgetTester tester) async {
    await app.pump(tester);
    await go(tester, 'Activity');
  }

  String idOf(String name) => app.services.registry.scope!.instances
      .firstWhere((active) => active.instance.name == name)
      .instance
      .id;

  Finder retry() => find.widgetWithText(TextButton, 'Retry');

  testWidgets("shows the client's figures beside the server's", (tester) async {
    await start(tester);
    films.items = [entry(1, 'A film', downloadId: 'ABC123')];
    client.torrents = [
      torrent(
        'abc123',
        progress: 0.637,
        speed: 4 * 1024 * 1024,
        eta: const Duration(minutes: 3),
      ),
    ];

    await open(tester);

    expect(find.text('50% · 1.5 GiB left · 5 min remaining'), findsOneWidget);
    expect(find.text('qBittorrent: 63% · Downloading'), findsOneWidget);
    expect(find.text('4.0 MiB/s · 3 min remaining'), findsOneWidget);
    expect(find.text('For the whole download'), findsNothing);

    client.torrents = [torrent('abc123', state: DownloadState.stalled)];
    await tester.pump(interval);
    await step(tester);
    expect(find.text('qBittorrent: 50% · Stalled'), findsOneWidget);
    expect(find.text('0 B/s'), findsOneWidget);

    client.torrents = [
      torrent('abc123', progress: 1, state: DownloadState.seeding),
    ];
    await tester.pump(interval);
    await step(tester);
    expect(find.text('qBittorrent: 100% · Seeding'), findsOneWidget);
    expect(find.textContaining('B/s'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('entries of one download say the figures are for all of it', (
    tester,
  ) async {
    await start(tester);
    films.items = [
      entry(1, 'Episode one', downloadId: 'pack'),
      entry(2, 'Episode two', downloadId: 'pack'),
    ];
    client.torrents = [torrent('pack')];

    await open(tester);

    expect(find.text('qBittorrent: 50% · Downloading'), findsNWidgets(2));
    expect(find.text('For the whole download'), findsNWidgets(2));

    await tester.tap(find.text('Episode one'));
    await step(tester);
    expect(find.text('qBittorrent: 50% · Downloading'), findsOneWidget);
    expect(find.text('For the whole download'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets("an entry no client has shows only the server's progress", (
    tester,
  ) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    client.torrents = [torrent('something else')];

    await open(tester);

    expect(find.text('50% · 1.5 GiB left · 5 min remaining'), findsOneWidget);
    expect(find.textContaining('qBittorrent'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('says that live progress is unavailable, and recovers', (
    tester,
  ) async {
    const notice = 'Live progress from qBittorrent is unavailable.';
    await start(tester);
    films.items = [entry(1, 'A film', downloadId: 'abc')];
    client.torrents = [torrent('abc')];
    await open(tester);

    client.failure = const Unreachable();
    await tester.pump(interval);
    await step(tester);

    expect(find.text(notice), findsOneWidget);
    // The old figures are not passed off as live ones.
    expect(find.textContaining('qBittorrent:'), findsNothing);
    expect(find.text('50% · 1.5 GiB left · 5 min remaining'), findsOneWidget);

    await tester.tap(find.text('A film'));
    await step(tester);
    expect(find.text(notice), findsOneWidget);

    client.failure = null;
    await tester.ensureVisible(retry());
    await step(tester);
    await tester.tap(retry());
    await step(tester);
    expect(find.text(notice), findsNothing);
    expect(find.text('qBittorrent: 50% · Downloading'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says nothing of a client that no entry could be in', (
    tester,
  ) async {
    await start(tester);
    films.items = [entry(1, 'A film', status: QueueStatus.delayed)];
    client.failure = const Unreachable();

    await open(tester);

    expect(find.textContaining('unavailable'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('reads only while the figures are on screen', (tester) async {
    await start(tester);
    films.items = [entry(1, 'A film', downloadId: 'abc')];
    client.torrents = [torrent('abc')];
    await app.pump(tester);
    await tester.pump(interval * 3);
    expect(client.reads, 0, reason: 'Activity was never opened');

    await go(tester, 'Activity');
    expect(client.reads, 1);
    await tester.pump(interval);
    expect(client.reads, 2);

    await go(tester, 'More');
    await tester.pump(interval * 3);
    expect(client.reads, 2);

    await go(tester, 'Activity');
    expect(client.reads, 3);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await step(tester);
    await tester.pump(interval * 5);
    expect(client.reads, 3);

    // Figures from before are not shown while the new ones are awaited.
    client.readGate = Completer();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await step(tester);
    expect(client.reads, 4);
    expect(find.textContaining('qBittorrent:'), findsNothing);
    client.readGate!.complete();
    await step(tester);
    expect(find.textContaining('qBittorrent:'), findsOneWidget);
    await app.stop(tester);
  });

  for (final latched in [true, false]) {
    testWidgets('a rejected sign-in is not tried again by itself ($latched)', (
      tester,
    ) async {
      await start(tester);
      films.items = [entry(1, 'A film', downloadId: 'abc')];
      client
        ..torrents = [torrent('abc')]
        ..failure = const AuthFailed();
      final id = idOf('Seedbox');
      if (latched) {
        await app.services.profiles.markAuthFailed(id);
        await app.services.registry.refresh();
      }

      await open(tester);
      final reads = client.reads;
      expect(reads, latched ? 0 : 1);
      await tester.pump(interval * 10);
      await go(tester, 'More');
      await go(tester, 'Activity');
      await tester.tap(find.byTooltip('Refresh the queue'));
      await step(tester);
      expect(client.reads, reads);
      expect(find.textContaining('unavailable'), findsOneWidget);

      client.failure = null;
      await tester.tap(retry());
      await step(tester);
      expect(client.reads, reads + 1);
      expect(find.text('qBittorrent: 50% · Downloading'), findsOneWidget);
      final saved = await tester.runAsync(
        () => app.services.profiles.instance(id),
      );
      expect(saved!.authFailed, isFalse);
      await app.stop(tester);
    });
  }

  testWidgets('of several clients, the first that has it is named', (
    tester,
  ) async {
    await start(tester, others: ['Second']);
    films.items = [
      entry(1, 'A film', downloadId: 'both'),
      entry(2, 'Another', downloadId: 'second'),
    ];
    client.torrents = [torrent('both', progress: 0.1)];
    clients.of('Second').torrents = [
      torrent('both', progress: 0.9),
      torrent('other', infohashV1: 'SECOND', progress: 0.2),
    ];

    await open(tester);

    expect(
      find.text('qBittorrent (Seedbox): 10% · Downloading'),
      findsOneWidget,
    );
    expect(
      find.text('qBittorrent (Second): 20% · Downloading'),
      findsOneWidget,
    );
    await app.stop(tester);
  });

  testWidgets('details open the library item', (tester) async {
    await start(
      tester,
      queues: QueueModule(
        library: FakeLibrary()
          ..route = (ref) => ModuleRoute(
            instanceId: ref.instanceId,
            path: 'films/items/${ref.remoteId}',
          ),
      ),
    );
    films.items = [
      entry(
        1,
        'A film',
        itemRef: ItemRef(
          instanceId: idOf('Films'),
          kind: MediaKind.movie,
          remoteId: 7,
        ),
      ),
      entry(2, 'Unknown to the server'),
    ];
    await open(tester);

    await tester.tap(find.text('Unknown to the server'));
    await step(tester);
    expect(find.text('Open in library'), findsNothing);
    await tester.pageBack();
    await step(tester);

    await tester.tap(find.text('A film'));
    await step(tester);
    await tester.ensureVisible(find.text('Open in library'));
    await step(tester);
    await tester.tap(find.text('Open in library'));
    await step(tester);
    expect(find.textContaining('Films item 7'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('fits large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester, others: ['Second'], size: const Size(320, 640));
    films.items = [entry(1, 'A film', downloadId: 'abc')];
    client.torrents = [torrent('abc', eta: const Duration(days: 3))];
    clients.of('Second').failure = const Unreachable();

    await open(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('A film'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await step(tester);
    await tester.tap(find.text('A film'));
    await step(tester);
    expect(find.text('Queue entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await app.stop(tester);
  });
}
