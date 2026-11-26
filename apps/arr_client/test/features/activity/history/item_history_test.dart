import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/support.dart';

/// The episodes of a series, as saved and as the server has them.
class FakeEpisodes implements LibraryProvider {
  var saved = <Episode>[];
  var onServer = <Episode>[];

  /// Fails the read from the server while set.
  ServiceFailure? failure;

  /// How often the server was asked.
  var reads = 0;

  @override
  MediaKind get itemKind => MediaKind.series;

  @override
  ServiceResult<List<LibraryItem>> children(ItemRef parent) async {
    reads++;
    final failure = this.failure;
    return failure == null ? Ok(onServer) : Err(failure);
  }

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedChildren(
    ItemRef parent,
  ) async => Ok(Cached(saved, fetchedAt: DateTime.utc(2026)));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A history that answers by page and records what it was asked.
class FakeHistory implements HistoryProvider {
  /// The events of each page, from 1.
  var pages = <List<HistoryEvent>>[[]];

  /// Fails every read while set.
  ServiceFailure? failure;

  /// Holds back every read while set.
  Completer<void>? gate;

  /// What was asked.
  final reads = <(MediaTarget?, int)>[];

  /// What was marked as failed.
  final marked = <int>[];

  @override
  ServiceResult<void> markFailed(int eventId) async {
    marked.add(eventId);
    return const Ok(null);
  }

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) async {
    reads.add((target, page));
    // As things were when asked.
    final failure = this.failure;
    final pages = this.pages;
    await gate?.future;
    if (failure != null) return Err(failure);
    return Ok(
      ResultPage(
        items: pages[page - 1],
        page: page,
        hasMore: page < pages.length,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HistoryModule extends FakeModule {
  HistoryModule()
    : super('films', offers: {CapabilityKind.history, CapabilityKind.library});

  final fake = FakeHistory();

  final episodes = FakeEpisodes();

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (HistoryProvider) => fake,
      const (LibraryProvider) => episodes,
      _ => null,
    };
    return found as T?;
  }
}

HistoryEvent event(
  int id, {
  HistoryEventType type = HistoryEventType.grabbed,
  String? title,
  int day = 1,
  ItemRef? itemRef,
  String? downloadId,
  Map<String, String> details = const {},
}) => HistoryEvent(
  id: id,
  eventType: type,
  date: DateTime.utc(2026, 3, day, 12),
  sourceTitle: title ?? 'Release $id',
  itemRef: itemRef,
  downloadId: downloadId,
  details: details,
);

/// Lets transitions and answers finish, also while a progress bar moves.
Future<void> step(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  late TestApp app;
  late HistoryModule module;
  late String instance;

  ItemRef movie() =>
      ItemRef(instanceId: instance, kind: MediaKind.movie, remoteId: 7);

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    void Function(FakeHistory fake)? arrange,
    void Function()? started,
    ItemRef Function()? item,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    module = HistoryModule();
    arrange?.call(module.fake);
    app = await TestApp.start(tester, modules: [module]);
    started?.call();
    instance = await app.add(module, 'Cellar');
    await app.pump(tester);
    app.services.registry.scope!
        .instance(instance)!
        .context
        .navigator
        .openHistory((item ?? movie)())
        .ignore();
    // Not pumpAndSettle, which would not end while a progress bar moves.
    await step(tester);
  }

  testWidgets('asks for the item and lists every kind of event', (
    tester,
  ) async {
    await open(
      tester,
      size: const Size(400, 2000),
      arrange: (fake) => fake.pages = [
        [
          for (final type in HistoryEventType.values)
            event(type.index + 1, type: type, day: 20 - type.index),
        ],
      ],
    );

    expect(module.fake.reads, [(MediaTarget(movie()), 1)]);
    expect(find.widgetWithText(AppBar, 'History'), findsOneWidget);
    final labels = [
      'Grabbed',
      'Imported',
      'Download failed',
      'File renamed',
      'File deleted',
      'Other event',
    ];
    final tops = [for (final it in labels) tester.getTopLeft(find.text(it)).dy];
    expect(tops, [...tops]..sort());
    expect(find.text('Release 1'), findsOneWidget);
    expect(find.textContaining('March 20, 2026'), findsOneWidget);
    expect(find.text('Show older events'), findsNothing);
    await app.stop(tester);
  });

  group('a series', () {
    ItemRef ref(MediaKind kind, int id) =>
        ItemRef(instanceId: instance, kind: kind, remoteId: id);

    Episode episode(int id, int season, int number) => Episode(
      ref: ref(MediaKind.episode, id),
      title: 'Part $number',
      sortTitle: 'part $number',
      monitored: true,
      state: ItemState.missing,
      seasonNumber: season,
      episodeNumber: number,
      hasFile: false,
    );

    void openSeries() => app.services.registry.scope!
        .instance(instance)!
        .context
        .navigator
        .openHistory(ref(MediaKind.series, 3))
        .ignore();

    /// A season pack and a special: the server records an event for each
    /// episode.
    Future<void> arrange(
      WidgetTester tester, {
      required void Function() episodes,
    }) async {
      await open(
        tester,
        size: const Size(400, 2000),
        item: () => ref(MediaKind.series, 3),
      );
      episodes();
      module.fake.pages = [
        [
          for (final id in [11, 12, 13])
            event(id, title: 'Pack', itemRef: ref(MediaKind.episode, id)),
        ],
      ];
      await tester.tap(find.byType(BackButton));
      await step(tester);
      openSeries();
      await step(tester);
    }

    testWidgets('says which episode each event is for', (tester) async {
      await arrange(
        tester,
        episodes: () => module.episodes.onServer = [
          episode(11, 2, 1),
          episode(12, 2, 2),
          episode(13, 0, 4),
        ],
      );

      expect(find.text('Season 2, episode 1'), findsOneWidget);
      expect(find.text('Season 2, episode 2'), findsOneWidget);
      expect(find.text('Special 4'), findsOneWidget);
      await app.stop(tester);
    });

    testWidgets('uses the saved episodes while they cannot be read', (
      tester,
    ) async {
      await arrange(
        tester,
        episodes: () => module.episodes
          ..saved = [episode(11, 1, 5)]
          ..failure = const Unreachable(),
      );

      expect(find.text('Season 1, episode 5'), findsOneWidget);
      expect(find.text('Pack'), findsNWidgets(3));
      await app.stop(tester);
    });

    testWidgets('no episodes are read for a movie', (tester) async {
      await open(tester);

      expect(module.episodes.reads, 0);
      await app.stop(tester);
    });
  });

  testWidgets('marks a grab as failed and reads the history again', (
    tester,
  ) async {
    await open(
      tester,
      size: const Size(400, 2000),
      arrange: (fake) => fake.pages = [
        [
          event(3, day: 3, downloadId: 'pack'),
          event(2, day: 2, downloadId: 'pack'),
          event(1, type: HistoryEventType.imported, downloadId: 'pack'),
        ],
      ],
    );
    expect(find.text('Mark as failed'), findsNWidgets(2));

    await tester.tap(find.text('Mark as failed').first);
    await step(tester);
    expect(find.textContaining('season pack'), findsOneWidget);
    expect(module.fake.marked, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Mark as failed'));
    await step(tester);

    expect(module.fake.marked, [3]);
    expect(module.fake.reads, hasLength(2));
    expect(
      find.text('Cellar accepted marking the download as failed.'),
      findsOneWidget,
    );
    await app.stop(tester);
  });

  testWidgets('shows named details only, as harmless text', (tester) async {
    await open(
      tester,
      size: const Size(400, 2000),
      arrange: (fake) => fake.pages = [
        [
          event(
            2,
            title: 'Film\u202Egpj.\u2066exe\u0007\nsecond',
            details: {
              'message': 'No\r\nspace\u200Fleft',
              'indexer': 'Index',
              'downloadClient': 'kind',
              'downloadClientName': 'Torrents',
              'releaseGroup': ' ',
              'indexerFlags': 'flags',
            },
          ),
          event(1, title: 'a' * 600),
        ],
      ],
    );

    expect(
      find.text('Film\u{fffd}gpj.\u{fffd}exe\u{fffd} second'),
      findsOneWidget,
    );
    expect(find.text('Message: No space\u{fffd}left'), findsOneWidget);
    expect(find.text('Indexer: Index'), findsOneWidget);
    expect(find.text('Download client: Torrents'), findsOneWidget);
    expect(find.textContaining('Release group'), findsNothing);
    expect(find.textContaining('kind'), findsNothing);
    expect(find.textContaining('flags'), findsNothing);
    expect(find.text('${'a' * 500}…'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('reads older pages on request, without repeats', (tester) async {
    await open(
      tester,
      arrange: (fake) => fake.pages = [
        [event(3, day: 3), event(2, day: 2)],
        [event(2, day: 2), event(1)],
      ],
    );
    expect(module.fake.reads, hasLength(1));

    await tester.tap(find.text('Show older events'));
    await step(tester);

    expect(module.fake.reads.last.$2, 2);
    expect(find.text('Release 2'), findsOneWidget);
    expect(find.text('Release 1'), findsOneWidget);
    expect(find.text('Show older events'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('keeps what it has when an older page fails', (tester) async {
    await open(
      tester,
      arrange: (fake) => fake.pages = [
        [event(2, day: 2)],
        [event(1)],
      ],
    );
    module.fake.failure = const Unreachable();
    await tester.tap(find.text('Show older events'));
    await step(tester);

    expect(find.text('Release 2'), findsOneWidget);
    expect(
      find.textContaining('Older events could not be loaded.'),
      findsOneWidget,
    );

    module.fake.failure = null;
    await tester.tap(find.text('Retry older events'));
    await step(tester);

    expect(find.text('Release 1'), findsOneWidget);
    expect(module.fake.reads.map((read) => read.$2), [1, 2, 2]);
    await app.stop(tester);
  });

  testWidgets('an older page that answers after a refresh is dropped', (
    tester,
  ) async {
    await open(
      tester,
      arrange: (fake) => fake.pages = [
        [event(2, day: 2)],
        [event(1)],
      ],
    );
    final slow = module.fake.gate = Completer<void>();
    await tester.tap(find.text('Show older events'));
    await step(tester);
    module.fake.gate = null;
    await tester.tap(find.byTooltip('Refresh the history'));
    await step(tester);
    slow.complete();
    await step(tester);

    expect(find.text('Release 1'), findsNothing);
    expect(find.text('Show older events'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says so while loading and when there is nothing', (
    tester,
  ) async {
    final gate = Completer<void>();
    await open(tester, arrange: (fake) => fake.gate = gate);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await step(tester);

    expect(find.text('This item has no history.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('offline, says why and reads again on retry', (tester) async {
    await open(
      tester,
      arrange: (fake) => fake
        ..failure = const Unreachable()
        ..pages = [
          [event(1)],
        ],
    );
    expect(find.textContaining('The server did not answer.'), findsOneWidget);

    module.fake.failure = null;
    await tester.tap(find.text('Retry'));
    await step(tester);

    expect(find.text('Release 1'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a failed refresh keeps the events, marked with their age', (
    tester,
  ) async {
    await open(
      tester,
      arrange: (fake) => fake.pages = [
        [event(2, day: 2)],
        [event(1)],
      ],
    );
    module.fake.failure = const Unreachable();
    await tester.tap(find.byTooltip('Refresh the history'));
    await step(tester);

    expect(find.text('Release 2'), findsOneWidget);
    expect(find.textContaining('Saved data from'), findsOneWidget);
    expect(find.textContaining('The server did not answer.'), findsOneWidget);
    final older = find.widgetWithText(TextButton, 'Show older events');
    expect(tester.widget<TextButton>(older).onPressed, isNull);
    await app.stop(tester);
  });

  testWidgets('says that a deleted item is gone', (tester) async {
    await open(tester, arrange: (fake) => fake.failure = const NotFound());

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
    await app.stop(tester);
  });

  testWidgets('has a deleted item forgotten', (tester) async {
    final gone = <ItemRef>[];
    late StreamSubscription<ItemRef> subscription;
    await open(
      tester,
      arrange: (fake) => fake.failure = const NotFound(),
      started: () =>
          subscription = app.services.cache.removals.listen(gone.add),
    );
    addTearDown(subscription.cancel);

    expect(gone, [movie()]);
    await app.stop(tester);
  });

  testWidgets('a route that names no item is explained', (tester) async {
    await open(tester);

    GoRouter.of(tester.element(find.byType(Scaffold).last))
        .go('/instances/$instance/history?kind=film&item=7');
    await step(tester);

    expect(find.text('This page does not exist.'), findsOneWidget);
    expect(module.fake.reads, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('fits a narrow screen with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    await open(
      tester,
      size: const Size(320, 640),
      arrange: (fake) => fake.pages = [
        [
          event(
            1,
            title: 'A.Very.Long.Release.Name.Without.Any.Space' * 4,
            details: {'message': 'It failed for a long reason. ' * 5},
          ),
        ],
        [],
      ],
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Show older events'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
    await app.stop(tester);
  });
}
