/// The library screen (spec story 2; FR-010, FR-074, FR-075).
library;

import 'dart:async';

import 'package:arr_client/app/app.dart';
import 'package:arr_client/features/library/library_controller.dart';
import 'package:arr_client/features/library/library_tiles.dart';
import 'package:arr_client/features/library/library_view_body.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/fake_library.dart';
import '../../app/navigation_test.dart' show open, usePhone;
import '../../app/support.dart';

/// The libraries by instance name, which a test fills before adding them.
final servers = <String, FakeLibrary>{};

final films = FakeModule(
  'movies',
  offers: {CapabilityKind.library},
  library: (context) => servers[context.instance.name]!,
);

Movie movie(
  String title, {
  int id = 0,
  String instance = 'x',
  ItemState state = ItemState.downloaded,
  bool monitored = true,
  int? year,
  DateTime? added,
  int size = 0,
  int? profile,
  Set<int> tags = const {},
}) => Movie(
  ref: ItemRef(
    instanceId: instance,
    kind: MediaKind.movie,
    remoteId: id == 0 ? title.hashCode : id,
  ),
  title: title,
  sortTitle: title.toLowerCase(),
  monitored: monitored,
  state: state,
  year: year,
  addedAt: added,
  sizeOnDisk: size,
  qualityProfileId: profile,
  tagIds: tags,
);

/// Adds an instance whose library is [library] and returns its id. Its items
/// are given that id, as an adapter would.
Future<String> addServer(
  TestApp app,
  String name,
  FakeLibrary library, {
  String? profileId,
}) async {
  servers[name] = library;
  final id = await app.add(films, name, profileId: profileId);
  List<LibraryItem> owned(List<LibraryItem> items) => [
    for (final item in items.cast<Movie>())
      movie(
        item.title,
        id: item.ref.remoteId,
        instance: id,
        state: item.state,
        monitored: item.monitored,
        year: item.year,
        added: item.addedAt,
        size: item.sizeOnDisk,
        profile: item.qualityProfileId,
        tags: item.tagIds,
      ),
  ];
  library.items = owned(library.items);
  if (library.cached case final cached?) {
    library.cached = Cached(owned(cached.value), fetchedAt: cached.fetchedAt);
  }
  return id;
}

Future<TestApp> start(WidgetTester tester, [Size? size]) async {
  usePhone(tester, size ?? const Size(400, 800));
  servers.clear();
  return TestApp.start(tester, modules: [films]);
}

Future<void> openLibrary(WidgetTester tester, TestApp app) async {
  await app.pump(tester);
  await open(tester, 'Library');
}

/// Pumps without waiting for animations, which never end while loading.
Future<void> pumpSome(WidgetTester tester) async {
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 500));
}

/// The titles of the tiles, in reading order.
List<String> shown(WidgetTester tester, List<String> candidates) {
  final found =
      [
        for (final title in candidates)
          if (find.text(title).evaluate().isNotEmpty)
            (title, tester.getTopLeft(find.text(title))),
      ]..sort((a, b) {
        final rows = a.$2.dy.compareTo(b.$2.dy);
        return rows != 0 ? rows : a.$2.dx.compareTo(b.$2.dx);
      });
  return [for (final (title, _) in found) title];
}

Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.filter_list));
  await tester.pumpAndSettle();
}

Future<void> closeSheet(WidgetTester tester) async {
  final done = find.textContaining(RegExp(r'^Show \d'));
  await tester.ensureVisible(done);
  await tester.pumpAndSettle();
  await tester.tap(done);
  await tester.pumpAndSettle();
}

Future<void> chooseSort(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Sort'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(CheckedPopupMenuItem<LibrarySort>, label),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows posters with their title and state', (tester) async {
    final app = await start(tester);
    await addServer(
      app,
      'Films',
      FakeLibrary(
        items: [
          movie('Alpha', year: 2001),
          movie('Beta', state: ItemState.missing),
          movie('Gamma', state: ItemState.unreleased),
          movie('Delta', state: ItemState.unmonitored),
          movie('Epsilon', state: ItemState.downloading),
        ],
      ),
    );
    final semantics = tester.ensureSemantics();

    await openLibrary(tester, app);

    expect(find.byType(SliverGrid), findsOneWidget);
    for (final state in [
      'Downloaded',
      'Missing',
      'Unreleased',
      'Unmonitored',
      'Downloading',
    ]) {
      expect(find.text(state), findsOneWidget);
    }
    expect(find.bySemanticsLabel('Alpha, 2001, Downloaded'), findsOneWidget);
    // One instance needs no label.
    expect(find.text('Films'), findsNothing);
    semantics.dispose();
    await app.stop(tester);
  });

  testWidgets('shows saved items with their age while the server is asked', (
    tester,
  ) async {
    final app = await start(tester);
    final library = FakeLibrary(
      items: [movie('Fresh')],
      cached: Cached([
        movie('Saved'),
      ], fetchedAt: DateTime.now().subtract(const Duration(hours: 2))),
    )..gate = Completer();
    await addServer(app, 'Films', library);

    await app.pump(tester);
    await tester.tap(find.text('Library'));
    await pumpSome(tester);

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Saved data from 2 hours ago'), findsOneWidget);

    library.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Fresh'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(find.textContaining('Saved data'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('one failing instance does not hide the others', (tester) async {
    final app = await start(tester);
    final broken = FakeLibrary(items: [movie('Hidden')])
      ..failure = const Unreachable();
    await addServer(app, 'Attic', broken);
    await addServer(app, 'Lounge', FakeLibrary(items: [movie('Visible')]));

    await openLibrary(tester, app);

    expect(find.text('Visible'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsOneWidget);
    // The notice names it, beside its choice among the services.
    expect(find.text('Attic'), findsNWidgets(2));

    broken.failure = null;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Hidden'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('a slow instance does not hold back the others', (tester) async {
    final app = await start(tester);
    final slow = FakeLibrary(items: [movie('Late')])..gate = Completer();
    await addServer(app, 'Attic', slow);
    await addServer(app, 'Lounge', FakeLibrary(items: [movie('Early')]));

    await app.pump(tester);
    await tester.tap(find.text('Library'));
    await pumpSome(tester);

    expect(find.text('Early'), findsOneWidget);
    expect(find.text('Loading Attic'), findsOneWidget);

    slow.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Loading Attic'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('choosing a service that is still loading keeps the way back', (
    tester,
  ) async {
    final app = await start(tester);
    final slow = FakeLibrary(items: [movie('Late')])..gate = Completer();
    final id = await addServer(app, 'Attic', slow);
    await addServer(app, 'Lounge', FakeLibrary(items: [movie('Early')]));
    await app.pump(tester);
    await tester.tap(find.text('Library'));
    await pumpSome(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Attic'));
    await pumpSome(tester);

    void expectScopedAndLoading() {
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.text('Loading Attic'), findsOneWidget);
      expect(find.text('Early'), findsNothing);
    }

    expectScopedAndLoading();

    // The saved scope is the same after a restart.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ArrClientApp(services: app.services));
    await pumpSome(tester);
    await tester.tap(find.text('Library'));
    await pumpSome(tester);
    expect(
      (await app.services.preferences.view(
        await app.activeProfile,
        MediaKind.movie,
      )).instanceScope,
      id,
    );
    expectScopedAndLoading();

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await pumpSome(tester);
    expect(find.text('Early'), findsOneWidget);

    slow.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Late'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('asks again on coming back to old data, not to fresh', (
    tester,
  ) async {
    final app = await start(tester);
    final library = FakeLibrary(items: [movie('Alpha')]);
    await addServer(app, 'Films', library);
    await openLibrary(tester, app);
    final controller = ProviderScope.containerOf(
      tester.element(find.byType(LibraryViewBody)),
    ).read(libraryProvider(MediaKind.movie).notifier);

    Future<void> leaveAndReturn() async {
      await open(tester, 'More');
      await open(tester, 'Library');
    }

    Future<void> resume() async {
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    await leaveAndReturn();
    await resume();
    expect(library.listed, 1);

    var later = Duration.zero;
    controller.now = () => DateTime.now().add(later);
    later = LibraryController.maxAge;
    await leaveAndReturn();
    expect(library.listed, 2);

    later = LibraryController.maxAge * 2 + const Duration(minutes: 1);
    await resume();
    expect(library.listed, 3);

    // Not while the library is out of sight.
    await open(tester, 'More');
    later = LibraryController.maxAge * 4;
    await resume();
    expect(library.listed, 3);
    await app.stop(tester);
  });

  testWidgets('keeps the saved items of an unreachable server', (tester) async {
    final app = await start(tester);
    final library = FakeLibrary(
      cached: Cached([
        movie('Saved'),
      ], fetchedAt: DateTime.now().subtract(const Duration(days: 3))),
    )..failure = const Unreachable();
    await addServer(app, 'Films', library);

    await openLibrary(tester, app);

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Saved data from 3 days ago'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('without saved items a failure takes the screen and can be '
      'retried', (tester) async {
    final app = await start(tester);
    final library = FakeLibrary(items: [movie('Back')])
      ..failure = const AuthFailed();
    await addServer(app, 'Films', library);

    await openLibrary(tester, app);
    expect(find.textContaining('sign-in was rejected'), findsOneWidget);

    library.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a refresh replaces the list, without a deleted item', (
    tester,
  ) async {
    final app = await start(tester);
    final library = FakeLibrary(items: [movie('Stays'), movie('Goes')]);
    await addServer(app, 'Films', library);
    await openLibrary(tester, app);

    library.items = [library.items.first];
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Stays'), findsOneWidget);
    expect(find.text('Goes'), findsNothing);
    expect(library.listed, 2);

    await tester.fling(find.text('Stays'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(library.listed, 3);
    await app.stop(tester);
  });

  testWidgets('says that the library is empty', (tester) async {
    final app = await start(tester);
    await addServer(app, 'Films', FakeLibrary());

    await openLibrary(tester, app);

    expect(find.text('No movies yet.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says that the one instance in view is empty', (tester) async {
    final app = await start(tester);
    await addServer(app, 'Full', FakeLibrary(items: [movie('Alpha')]));
    await addServer(app, 'Bare', FakeLibrary());
    await openLibrary(tester, app);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bare'));
    await tester.pumpAndSettle();

    expect(find.text('No movies yet.'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('the same title in two instances shows which is which', (
    tester,
  ) async {
    final app = await start(tester);
    await addServer(app, 'HD', FakeLibrary(items: [movie('Heat')]));
    final uhd = await addServer(app, '4K', FakeLibrary(items: [movie('Heat')]));

    await openLibrary(tester, app);

    expect(find.text('Heat'), findsNWidgets(2));
    // On the tile and on the choice of services.
    expect(find.text('HD'), findsNWidgets(2));
    expect(find.text('4K'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ChoiceChip, '4K'));
    await tester.pumpAndSettle();

    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('HD'), findsOneWidget);
    final view = await app.services.preferences.view(
      await app.activeProfile,
      MediaKind.movie,
    );
    expect(view.instanceScope, uhd);
    await app.stop(tester);
  });

  testWidgets('the filter box narrows the list and is remembered', (
    tester,
  ) async {
    final app = await start(tester);
    await addServer(
      app,
      'Films',
      FakeLibrary(items: [movie('Alien'), movie('Heat')]),
    );
    await openLibrary(tester, app);

    await tester.enterText(find.byType(TextField), 'hea');
    await tester.pumpAndSettle();

    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('Alien'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches these filters.'), findsOneWidget);

    // The app is started again.
    await tester.pumpWidget(const SizedBox.shrink());
    await openLibrary(tester, app);
    expect(find.widgetWithText(TextField, 'zzz'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(find.text('Alien'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'zzz'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('filters by state, monitoring, quality profile and tag', (
    tester,
  ) async {
    final app = await start(tester);
    await addServer(
      app,
      'Films',
      FakeLibrary(
        items: [
          movie('Alpha', profile: 1, tags: {1}),
          movie('Beta', state: ItemState.missing, monitored: false),
          movie('Gamma', state: ItemState.missing, profile: 2),
        ],
        serverOptions: const [
          ServerOption(
            kind: ServerOptionKind.qualityProfile,
            id: 1,
            label: 'HD',
          ),
          ServerOption(
            kind: ServerOptionKind.qualityProfile,
            id: 2,
            label: 'Ultra',
          ),
          ServerOption(kind: ServerOptionKind.tag, id: 1, label: 'kids'),
        ],
      ),
    );
    await openLibrary(tester, app);
    const all = ['Alpha', 'Beta', 'Gamma'];

    Future<List<String>> filtered(List<String> chips) async {
      await openFilters(tester);
      for (final chip in chips) {
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(chip),
          ),
        );
        await tester.pumpAndSettle();
      }
      await closeSheet(tester);
      final result = shown(tester, all);
      await openFilters(tester);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await closeSheet(tester);
      return result;
    }

    expect(await filtered(['Missing']), ['Beta', 'Gamma']);
    expect(await filtered(['Not monitored']), ['Beta']);
    expect(await filtered(['Ultra']), ['Gamma']);
    expect(await filtered(['kids']), ['Alpha']);
    expect(await filtered(['Missing', 'Monitored']), ['Gamma']);
    expect(shown(tester, all), all);
    await app.stop(tester);
  });

  testWidgets('counts the filters that are on', (tester) async {
    final app = await start(tester);
    await addServer(app, 'Films', FakeLibrary(items: [movie('Alpha')]));
    await openLibrary(tester, app);

    await openFilters(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Downloaded'));
    await tester.pump();
    await tester.tap(find.text('Monitored'));
    await tester.pumpAndSettle();
    await closeSheet(tester);

    expect(find.byTooltip('Filters, 2 on'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('drops a saved filter id the server no longer has', (
    tester,
  ) async {
    final app = await start(tester);
    final id = await addServer(
      app,
      'Films',
      FakeLibrary(
        items: [movie('Alpha', profile: 1)],
        serverOptions: const [
          ServerOption(
            kind: ServerOptionKind.qualityProfile,
            id: 1,
            label: 'HD',
          ),
        ],
      ),
    );
    final profile = await app.activeProfile;
    await app.services.preferences.saveView(
      profile,
      MediaKind.movie,
      LibraryView(
        filters: LibraryFilters(
          qualityProfiles: {InstanceOptionId(id, 99)},
          tags: {InstanceOptionId(id, 99)},
        ),
      ),
    );

    await openLibrary(tester, app);

    expect(find.text('Alpha'), findsOneWidget);
    final view = await app.services.preferences.view(profile, MediaKind.movie);
    expect(view.filters, const LibraryFilters());
    await app.stop(tester);
  });

  testWidgets('keeps the saved ids of a server whose options cannot be read', (
    tester,
  ) async {
    final app = await start(tester);
    final library = FakeLibrary(items: [movie('Alpha', profile: 7)])
      ..optionsFailure = const Unreachable();
    final id = await addServer(app, 'Films', library);
    final profile = await app.activeProfile;
    final saved = LibraryView(
      filters: LibraryFilters(qualityProfiles: {InstanceOptionId(id, 7)}),
    );
    await app.services.preferences.saveView(profile, MediaKind.movie, saved);

    await openLibrary(tester, app);
    await openFilters(tester);

    // The choice can still be seen and taken off.
    expect(find.text('Unavailable profile 7'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsOneWidget);
    expect(
      await app.services.preferences.view(profile, MediaKind.movie),
      saved,
    );
    await app.stop(tester);
  });

  testWidgets('sorts, and each profile keeps its own view', (tester) async {
    final app = await start(tester);
    const titles = ['Alpha', 'Beta', 'Gamma'];
    await addServer(
      app,
      'Films',
      FakeLibrary(
        items: [
          movie('Alpha', year: 2000, size: 1 << 30, added: DateTime.utc(2024)),
          movie('Beta', year: 2020, size: 3 << 30, added: DateTime.utc(2025)),
          movie('Gamma', year: 2010, size: 2 << 30, added: DateTime.utc(2026)),
        ],
      ),
    );
    final away = await app.addProfile('Away');
    await addServer(
      app,
      'Cabin',
      FakeLibrary(items: [movie('Alpha'), movie('Beta')]),
      profileId: away,
    );
    await openLibrary(tester, app);
    expect(shown(tester, titles), titles);

    await chooseSort(tester, 'Year');
    expect(shown(tester, titles), ['Beta', 'Gamma', 'Alpha']);
    await chooseSort(tester, 'Ascending');
    expect(shown(tester, titles), ['Alpha', 'Gamma', 'Beta']);
    await chooseSort(tester, 'Date added');
    expect(shown(tester, titles), ['Gamma', 'Beta', 'Alpha']);
    await chooseSort(tester, 'Size on disk');
    await tester.tap(find.byTooltip('Show as list'));
    await tester.pumpAndSettle();
    expect(shown(tester, titles), ['Beta', 'Gamma', 'Alpha']);
    expect(find.textContaining('3.0 GiB'), findsOneWidget);

    final home = await app.activeProfile;
    await app.services.registry.switchTo(away);
    await tester.pumpAndSettle();
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(shown(tester, titles), ['Alpha', 'Beta']);

    await app.services.registry.switchTo(home);
    await tester.pumpAndSettle();
    expect(find.byType(SliverGrid), findsNothing);
    expect(shown(tester, titles), ['Beta', 'Gamma', 'Alpha']);
    final view = await app.services.preferences.view(home, MediaKind.movie);
    expect(view.layout, LibraryLayout.list);
    expect(view.sort, const LibrarySort(field: 'size', ascending: false));
    await app.stop(tester);
  });

  testWidgets('an item without a module screen yet opens a placeholder', (
    tester,
  ) async {
    final app = await start(tester);
    await addServer(app, 'Films', FakeLibrary(items: [movie('Alpha')]));
    await openLibrary(tester, app);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Alpha'), findsOneWidget);
    expect(find.textContaining('not built yet'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('an item opens the screen its module routes to', (tester) async {
    final app = await start(tester);
    await addServer(
      app,
      'Films',
      FakeLibrary(items: [movie('Alpha', id: 7)])
        ..route = (ref) => ModuleRoute(
          instanceId: ref.instanceId,
          path: 'movies/items/${ref.remoteId}',
          query: {'from': 'library'},
        ),
    );
    await openLibrary(tester, app);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Films item 7 library'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('builds only what is on screen of 10,000 movies', (tester) async {
    final app = await start(tester);
    // As many as tool/gen_large_library.dart makes, which a test of the app
    // may not import.
    final items = [
      for (var id = 1; id <= 10000; id++)
        movie('Film ${'$id'.padLeft(5, '0')}', id: id, year: 1950 + id % 76),
    ];
    await addServer(app, 'Films', FakeLibrary(items: items));
    await openLibrary(tester, app);

    int tiles() => find.byType(LibraryGridTile).evaluate().length;
    expect(tiles(), inInclusiveRange(6, 40));

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      8000,
    );
    await tester.pumpAndSettle();
    expect(tiles(), inInclusiveRange(6, 40));

    await tester.enterText(find.byType(TextField), '09999');
    await tester.pumpAndSettle();
    expect(tiles(), 1);
    await app.stop(tester);
  });

  for (final size in [const Size(320, 640), const Size(800, 360)]) {
    testWidgets('nothing overflows at 200% text on $size', (tester) async {
      final app = await start(tester, size);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final long = 'A very long title that goes on and on ' * 3;
      await addServer(
        app,
        'An instance with a rather long name',
        FakeLibrary(
          items: [movie(long, year: 2000, state: ItemState.unmonitored)],
          serverOptions: [
            ServerOption(
              kind: ServerOptionKind.qualityProfile,
              id: 1,
              label: long,
            ),
          ],
        ),
      );
      final broken = FakeLibrary(
        cached: Cached([movie(long)], fetchedAt: DateTime.utc(2026)),
      )..failure = const Unreachable();
      await addServer(app, 'Second', broken);

      await app.pump(tester);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Show as list'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await openFilters(tester);
      expect(tester.takeException(), isNull);
      await app.stop(tester);
    });
  }

  testWidgets('meets the tap target and label guidelines', (tester) async {
    final app = await start(tester);
    final semantics = tester.ensureSemantics();
    await addServer(app, 'Films', FakeLibrary(items: [movie('Alpha')]));
    await addServer(app, 'More films', FakeLibrary(items: [movie('Beta')]));
    await openLibrary(tester, app);
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pumpAndSettle();

    for (final layout in ['Show as list', 'Show as grid']) {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.byTooltip(layout));
      await tester.pumpAndSettle();
    }
    await openFilters(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
    await app.stop(tester);
  });
}
