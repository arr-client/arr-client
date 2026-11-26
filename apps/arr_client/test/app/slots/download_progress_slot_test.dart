/// The downloads on a detail screen (spec story 7, the item's details).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/activity/queue/support.dart';
import '../support.dart';

const interval = Duration(seconds: 4);

const title = 'In the queue';

/// A service whose detail screens are nothing but the slot, as a module places
/// it.
class DetailModule extends QueueModule {
  @override
  List<ModuleScreen> routes() => [
    ModuleScreen(
      path: 'films/detail/:kind/:itemId',
      builder: (context, instance, parameters) => Scaffold(
        appBar: AppBar(),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            DetailSlot(
              DetailSlotName.downloadProgress,
              item: ItemRef(
                instanceId: instance.instance.id,
                kind: MediaKind.values.byName(parameters['kind']!),
                remoteId: int.parse(parameters['itemId']!),
              ),
            ),
          ],
        ),
      ),
    ),
  ];
}

void main() {
  late DetailModule module;
  late ProgressModule clients;
  late TestApp app;
  late FakeQueue films;
  late FakeProgress client;

  /// The app with the queues of "Films" and "Others", and the download client
  /// "Seedbox" unless told, on a screen that reads neither.
  Future<void> start(
    WidgetTester tester, {
    bool withClient = true,
    Size size = const Size(400, 800),
  }) async {
    useScreen(tester, size);
    module = DetailModule();
    clients = ProgressModule();
    films = module.of('Films');
    client = clients.of('Seedbox');
    app = await TestApp.start(tester, modules: [module, clients]);
    await app.add(module, 'Films');
    await app.add(module, 'Others');
    if (withClient) await app.add(clients, 'Seedbox');
    await app.pump(tester);
    // Home shows the queues itself.
    await go(tester, 'More');
    films.reads = 0;
    module.of('Others').reads = 0;
  }

  String idOf(String name) => app.services.registry.scope!.instances
      .firstWhere((active) => active.instance.name == name)
      .instance
      .id;

  ItemRef refTo(MediaKind kind, int id) =>
      ItemRef(instanceId: idOf('Films'), kind: kind, remoteId: id);

  Future<void> open(WidgetTester tester, MediaKind kind, int id) async {
    unawaited(
      app.services.navigator.router!.push<void>(
        '/instances/${idOf('Films')}/films/detail/${kind.name}/$id',
      ),
    );
    await step(tester);
  }

  QueueItem movie(int id, int movieId, {String? downloadId = 'own'}) => entry(
    id,
    'Release $id',
    downloadId: downloadId,
    itemRef: refTo(MediaKind.movie, movieId),
  );

  testWidgets("shows the movie's download with the client's figures", (
    tester,
  ) async {
    await start(tester);
    films.items = [
      movie(1, 7, downloadId: 'ABC'),
      movie(2, 8, downloadId: 'def'),
    ];
    client.torrents = [
      torrent(
        'abc',
        progress: 0.637,
        speed: 4 * 1024 * 1024,
        eta: const Duration(minutes: 3),
      ),
      torrent('def'),
    ];

    await open(tester, MediaKind.movie, 7);

    expect(find.text(title), findsOneWidget);
    expect(find.text('Release 1'), findsOneWidget);
    expect(find.text('Release 2'), findsNothing);
    expect(find.text('50% · 1.5 GiB left · 5 min remaining'), findsOneWidget);
    expect(find.text('qBittorrent: 63% · Downloading'), findsOneWidget);
    expect(find.text('4.0 MiB/s · 3 min remaining'), findsOneWidget);
    expect(find.text('For the whole download'), findsNothing);
    expect(module.of('Others').reads, 0, reason: "not this item's instance");

    client.torrents = [torrent('abc', progress: 0.9)];
    await tester.pump(interval);
    await step(tester);
    expect(find.text('qBittorrent: 90% · Downloading'), findsOneWidget);

    await tester.tap(find.text('Release 1'));
    await step(tester);
    expect(find.text('Queue entry'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a season pack is shown once for its series, and says that the '
      'figures are for all of it', (tester) async {
    await start(tester);
    films.items = [
      for (var id = 1; id <= 3; id++)
        entry(
          id,
          'Season pack',
          downloadId: 'pack',
          itemRef: refTo(MediaKind.episode, id),
          parent: refTo(MediaKind.series, 5),
        ),
    ];
    client.torrents = [torrent('pack')];

    await open(tester, MediaKind.series, 5);

    expect(find.text('Season pack'), findsOneWidget);
    expect(find.text('3 queue entries'), findsOneWidget);
    expect(find.text('qBittorrent: 50% · Downloading'), findsOneWidget);
    expect(find.text('For the whole download'), findsOneWidget);

    app.services.navigator.router!.pop();
    await step(tester);
    await open(tester, MediaKind.episode, 2);

    expect(find.text('Season pack'), findsOneWidget);
    expect(find.textContaining('queue entries'), findsNothing);
    expect(find.text('For the whole download'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets("a Usenet download has the server's progress only, and no "
      'client is read for it', (tester) async {
    await start(tester);
    films.items = [
      QueueItem(
        id: 1,
        title: 'From Usenet',
        status: QueueStatus.downloading,
        trackedState: TrackedState.downloading,
        severity: QueueSeverity.ok,
        progress: 0.25,
        sizeLeft: 0,
        protocol: DownloadProtocol.usenet,
        downloadId: 'nzb',
        itemRef: refTo(MediaKind.movie, 7),
      ),
    ];
    client.failure = const Unreachable();

    await open(tester, MediaKind.movie, 7);
    await tester.pump(interval * 2);

    expect(find.text('25%'), findsOneWidget);
    expect(find.textContaining('qBittorrent'), findsNothing);
    expect(client.reads, 0);
    await app.stop(tester);
  });

  testWidgets('says that live progress is unavailable, and recovers', (
    tester,
  ) async {
    const notice = 'Live progress from qBittorrent is unavailable.';
    await start(tester);
    films.items = [movie(1, 7, downloadId: 'abc')];
    client
      ..torrents = [torrent('abc')]
      ..failure = const Unreachable();

    await open(tester, MediaKind.movie, 7);

    expect(find.text(notice), findsOneWidget);
    expect(find.text('50% · 1.5 GiB left · 5 min remaining'), findsOneWidget);

    client.failure = null;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await step(tester);
    expect(find.text(notice), findsNothing);
    expect(find.text('qBittorrent: 50% · Downloading'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says that the queue shown is old when it cannot be read', (
    tester,
  ) async {
    await start(tester);
    films.items = [movie(1, 7)];
    await open(tester, MediaKind.movie, 7);

    films.failure = const Unreachable();
    await tester.pump(interval);
    await step(tester);

    expect(find.text('Release 1'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    films.failure = null;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await step(tester);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('is empty for an item with nothing queued, and reads no client', (
    tester,
  ) async {
    await start(tester);
    films.items = [movie(1, 8)];

    await open(tester, MediaKind.movie, 7);
    await tester.pump(interval);

    expect(find.text(title), findsNothing);
    expect(films.reads, 2);
    expect(client.reads, 0);
    await app.stop(tester);
  });

  testWidgets('without a download client it is empty and reads nothing', (
    tester,
  ) async {
    await start(tester, withClient: false);
    films.items = [movie(1, 7)];

    await open(tester, MediaKind.movie, 7);
    await tester.pump(interval * 2);

    expect(find.text(title), findsNothing);
    expect(films.reads, 0);
    await app.stop(tester);
  });

  testWidgets('reads only while it is on screen', (tester) async {
    await start(tester);
    films.items = [movie(1, 7, downloadId: 'abc')];
    client.torrents = [torrent('abc')];
    await tester.pump(interval * 2);
    expect((films.reads, client.reads), (0, 0));

    await open(tester, MediaKind.movie, 7);
    await tester.pump(interval);
    await step(tester);
    expect((films.reads, client.reads), (2, 2));

    // Covered by another page.
    unawaited(app.services.navigator.router!.push<void>('/profiles'));
    await step(tester);
    await tester.pump(interval * 3);
    expect((films.reads, client.reads), (2, 2));

    app.services.navigator.router!.pop();
    await step(tester);
    expect((films.reads, client.reads), (3, 3));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await step(tester);
    await tester.pump(interval * 3);
    expect((films.reads, client.reads), (3, 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await step(tester);
    expect((films.reads, client.reads), (4, 4));

    app.services.navigator.router!.pop();
    await step(tester);
    await tester.pump(interval * 3);
    expect((films.reads, client.reads), (4, 4));
    expect(module.of('Others').reads, 0);
    await app.stop(tester);
  });

  testWidgets('the queue tab still reads every queue, and then only its own', (
    tester,
  ) async {
    await start(tester);
    films.items = [movie(1, 7)];
    final others = module.of('Others');
    await go(tester, 'Activity');
    expect((films.reads, others.reads), (1, 1));

    await open(tester, MediaKind.movie, 7);
    await tester.pump(interval * 2);
    await step(tester);
    expect(films.reads, greaterThan(2));
    expect(others.reads, 1);

    app.services.navigator.router!.pop();
    await step(tester);
    expect(others.reads, 2);
    await app.stop(tester);
  });

  testWidgets('fits large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester, size: const Size(320, 640));
    films.items = [
      movie(1, 7, downloadId: 'abc'),
      movie(2, 7, downloadId: 'abc'),
      movie(3, 7),
    ];
    client.torrents = [torrent('abc', eta: const Duration(days: 3))];

    await open(tester, MediaKind.movie, 7);

    expect(find.text(title), findsOneWidget);
    expect(tester.takeException(), isNull);
    await app.stop(tester);
  });
}
