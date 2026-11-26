// The series, season and episode screens (T057).

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sonarr/sonarr_module.dart';
import 'package:sonarr/src/screens/series_detail.dart';
import 'package:sonarr/src/screens/sonarr_sources.dart';

import '../contract/support.dart';
import 'support.dart';

/// What the recorded server calls series 1.
const _title = 'redacted-1';

ModuleRoute _route(Screens screens, ItemRef ref) =>
    screens.harness.library.detailRoute(ref);

ModuleRoute _season(int number) => ModuleRoute(
  instanceId: instanceId,
  path: 'sonarr/series/1/seasons/$number',
);

void _smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('series and episodes have detail routes of their own', () {
    final library = Screens().harness.library;

    expect(
      library.detailRoute(seriesRef(1)).location,
      '/instances/i1/sonarr/series/1',
    );
    expect(
      library.detailRoute(episodeRef(13)).location,
      '/instances/i1/sonarr/episodes/13',
    );
    expect(
      () => library.detailRoute(
        const ItemRef(
          instanceId: instanceId,
          kind: MediaKind.movie,
          remoteId: 1,
        ),
      ),
      throwsArgumentError,
    );
  });

  testWidgets('screens keep their state when the context is built anew', (
    tester,
  ) async {
    final screens = Screens();
    await screens.open(tester, _route(screens, seriesRef(1)));
    final given = screens.harness.context;
    final context = tester.element(find.byType(Scaffold).last);
    final renamed = InstanceContext(
      instance: given.instance,
      http: given.http,
      artwork: given.artwork,
      navigator: given.navigator,
      cache: given.cache,
      logger: given.logger,
    );

    final module = SonarrModule().routes().first;
    SonarrSources sources(InstanceContext instance) => (module.builder(
      context,
      instance,
      {'seriesId': '1'},
    ) as SeriesDetailScreen).sources;

    expect(sources(renamed), same(sources(given)));
  });

  testWidgets('a series shows its facts, seasons, history and slots', (
    tester,
  ) async {
    final screens = Screens();
    await screens.open(tester, _route(screens, seriesRef(1)));

    expect(find.text(_title), findsNWidgets(2)); // App bar and header.
    expect(find.text('1962 · Ended'), findsOneWidget);
    expect(find.text('Monitored'), findsOneWidget);
    expect(screens.slots.map((slot) => (slot.name, slot.item)).toSet(), {
      (DetailSlotName.downloadProgress, seriesRef(1)),
      (DetailSlotName.subtitles, seriesRef(1)),
    });

    await scrollTo(tester, find.text('Rating'));
    // Sonarr does not say whose score it is.
    expect(find.text('7.3 · 12,680 votes'), findsOneWidget);
    await scrollTo(tester, find.text('Quality profile'));
    final profile = screens.server.qualityProfiles.singleWhere(
      (p) => p['id'] == 6,
    );
    expect(find.text(profile['name']! as String), findsOneWidget);

    await scrollTo(tester, find.text('3 of 36 episodes'));
    expect(find.text('Season 1'), findsOneWidget);
    // Specials come after the numbered seasons.
    await scrollTo(tester, find.text('Specials'));
    expect(
      tester.getTopLeft(find.text('Specials')).dy,
      greaterThan(
        tester.getTopLeft(find.text('Season 1', skipOffstage: false)).dy,
      ),
    );
    expect(find.text('12 episodes'), findsOneWidget);

    await scrollTo(tester, find.text('Show all history'));
    expect(find.textContaining('Download failed'), findsOneWidget);
    await tester.tap(find.text('Show all history'));
    expect(screens.navigator.histories, [seriesRef(1)]);
  });

  testWidgets('a season lists its episodes, which open', (tester) async {
    final screens = Screens();
    await screens.open(tester, _route(screens, seriesRef(1)));
    await scrollTo(tester, find.text('Season 1'));
    await tester.tap(find.text('Season 1'));
    await tester.pumpAndSettle();

    expect(find.text('1. redacted-58'), findsOneWidget);
    expect(find.textContaining('HDTV-720p'), findsWidgets);
    expect(find.text('Missing'), findsWidgets);
    // Another season's.
    expect(find.text('1. redacted-88'), findsNothing);
    // The series screen had read the episodes already.
    expect(
      screens.server.requests.where((r) => r.path == 'api/v3/episode'),
      hasLength(1),
    );

    screens.slots.clear();
    await tester.tap(find.text('1. redacted-58'));
    await tester.pumpAndSettle();

    expect(find.text('Season 1, episode 1'), findsNWidgets(2));
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(
      screens.slots.map((slot) => (slot.name, slot.item, slot.parent)).toSet(),
      {
        (DetailSlotName.downloadProgress, episodeRef(13), seriesRef(1)),
        (DetailSlotName.subtitles, episodeRef(13), seriesRef(1)),
      },
    );
    await scrollTo(tester, find.text('Quality'));
    expect(find.text('HDTV-720p'), findsOneWidget);
    expect(find.text('No file'), findsNothing);
  });

  testWidgets('season 0 holds the specials', (tester) async {
    final screens = Screens();
    await screens.open(tester, _season(0));

    expect(find.text('Specials'), findsOneWidget);
    expect(find.text('1. redacted-54'), findsOneWidget);
    await tester.tap(find.text('1. redacted-54'));
    await tester.pumpAndSettle();

    expect(find.text('Special 1'), findsNWidgets(2));
    await scrollTo(tester, find.text('No file'));
  });

  testWidgets('an episode opened on its own links to its series', (
    tester,
  ) async {
    final screens = Screens();
    // As the calendar opens it.
    await screens.open(tester, _route(screens, episodeRef(13)));

    await tester.tap(find.widgetWithText(ListTile, _title));
    await tester.pumpAndSettle();

    expect(find.text('1962 · Ended'), findsOneWidget);
  });

  testWidgets('a season without episodes says so', (tester) async {
    final screens = Screens();
    await screens.open(tester, _season(40));

    expect(find.text('No episodes in this season'), findsOneWidget);
  });

  testWidgets('what was saved stays, with its age, while offline', (
    tester,
  ) async {
    final screens = Screens();
    await screens.open(tester, _route(screens, seriesRef(1)));
    await screens.back(tester);
    screens.server.goOffline();

    await screens.open(tester, _route(screens, seriesRef(1)));

    expect(find.textContaining('Saved data from'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsWidgets);
    expect(find.text(_title), findsNWidgets(2));

    // The episodes were saved too.
    await screens.open(tester, _season(1));
    expect(find.text('1. redacted-58'), findsOneWidget);
    expect(find.textContaining('Saved data from'), findsOneWidget);

    screens.server.always = null;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved data from'), findsNothing);
  });

  testWidgets('with nothing saved, a failure can be retried', (tester) async {
    final screens = Screens()..server.goOffline();
    await screens.open(tester, _route(screens, episodeRef(13)));

    expect(find.textContaining('did not answer'), findsOneWidget);
    screens.server.always = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('redacted-58'), findsOneWidget);
  });

  testWidgets('history that cannot be read can be asked for again', (
    tester,
  ) async {
    final screens = Screens();
    screens.server.overrides['history/series'] = FakeSonarr.body(
      '{}',
      status: 500,
    );
    await screens.open(tester, _route(screens, seriesRef(1)));

    await scrollTo(tester, find.text('Retry history'));
    expect(find.text('History could not be loaded.'), findsOneWidget);
    screens.server.overrides.clear();
    await tester.tap(find.text('Retry history'));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Show all history'));
  });

  testWidgets('a series deleted on the server is said to be gone', (
    tester,
  ) async {
    final screens = Screens();
    await screens.open(tester, _route(screens, seriesRef(1)));
    await screens.back(tester);
    screens.server.series.removeWhere((series) => series['id'] == 1);

    await screens.open(tester, _route(screens, seriesRef(1)));

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
    expect(await screens.harness.cache.entry(MediaKind.series, 1), isNull);
  });

  testWidgets('an address that names no item is said to be gone', (
    tester,
  ) async {
    final screens = Screens();
    await screens.open(
      tester,
      const ModuleRoute(instanceId: instanceId, path: 'sonarr/series/x'),
    );

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
    expect(screens.server.requests, isEmpty);
  });

  testWidgets('a long season builds only the episodes near the screen', (
    tester,
  ) async {
    final server = FakeSonarr();
    final pattern = jsonEncode(
      server.episodes[1]!.firstWhere((e) => e['id'] == 13),
    );
    server.episodes[1] = [
      for (var number = 1; number <= 800; number++)
        {
          ...jsonDecode(pattern) as Map<String, Object?>,
          'id': 1000 + number,
          'episodeNumber': number,
          'title': 'Part $number',
        },
    ];
    final screens = Screens(server: server);
    await screens.open(tester, _season(1));

    expect(find.text('1. Part 1'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(20));
    expect(find.text('800. Part 800', skipOffstage: false), findsNothing);
  });

  testWidgets('every screen fits a small phone at twice the text size', (
    tester,
  ) async {
    _smallPhone(tester);
    final handle = tester.ensureSemantics();
    final screens = Screens();

    for (final route in [
      _route(screens, seriesRef(1)),
      _season(1),
      _route(screens, episodeRef(13)),
    ]) {
      await screens.open(tester, route, textScale: 2);
      // Everything is laid out on the way down: an overflow fails the test.
      final scrollable = find.byType(Scrollable).last;
      for (var page = 0; page < 30; page++) {
        await tester.drag(scrollable, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await screens.back(tester);
    }
    handle.dispose();
  });
}
