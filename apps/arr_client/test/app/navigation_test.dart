/// Capability-driven navigation (contracts/navigation.md, spec story 1).
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support.dart';

void usePhone(WidgetTester tester, [Size size = const Size(400, 800)]) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The labels of the bottom bar.
List<String> bar(WidgetTester tester) => [
  for (final destination
      in tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .cast<NavigationDestination>())
    destination.label,
];

List<String?> tabs(WidgetTester tester) => [
  for (final tab in tester.widgetList<Tab>(find.byType(Tab))) tab.text,
];

Future<void> open(WidgetTester tester, String destination) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(destination),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without an instance Home is onboarding, with More beside it', (
    tester,
  ) async {
    usePhone(tester);
    final app = await TestApp.start(tester);

    await app.pump(tester);

    expect(bar(tester), ['Home', 'More']);
    expect(find.textContaining('No services yet'), findsOneWidget);
    expect(find.byTooltip('Search'), findsNothing);
    await open(tester, 'More');
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    for (final entry in ['Calendar', 'Wanted', 'Blocklist', 'Subtitles']) {
      expect(find.text(entry), findsNothing);
    }
    await app.stop(tester);
  });

  testWidgets('only what the instances offer appears, and goes with them', (
    tester,
  ) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.pump(tester);

    final films = await app.add(movies, 'Films');
    await tester.pumpAndSettle();

    expect(bar(tester), ['Home', 'Library', 'Activity', 'More']);
    expect(find.textContaining('No services yet'), findsNothing);
    expect(find.byTooltip('Search'), findsOneWidget);
    await open(tester, 'Library');
    expect(tabs(tester), ['Movies']);
    await open(tester, 'Activity');
    expect(tabs(tester), ['Queue', 'History']);
    await open(tester, 'More');
    expect(find.text('Blocklist'), findsOneWidget);
    expect(find.text('Calendar'), findsNothing);

    await app.add(series, 'Shows');
    await tester.pumpAndSettle();

    expect(find.text('Calendar'), findsOneWidget);
    await open(tester, 'Library');
    expect(tabs(tester), ['Movies', 'Series']);

    await app.services.profiles.deleteInstance(films);
    await tester.pumpAndSettle();

    expect(tabs(tester), ['Series']);
    expect(bar(tester), ['Home', 'Library', 'More']);
    await app.stop(tester);
  });

  testWidgets('a destination that goes away is left for Home', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    final films = await app.add(movies, 'Films');
    await app.pump(tester);
    await open(tester, 'Library');

    await app.services.profiles.deleteInstance(films);
    await tester.pumpAndSettle();

    expect(bar(tester), ['Home', 'More']);
    expect(find.textContaining('No services yet'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a disabled instance contributes nothing', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films', enabled: false);

    await app.pump(tester);

    expect(bar(tester), ['Home', 'More']);
    // It has an instance, so this is not onboarding.
    expect(find.textContaining('No services yet'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('a download client adds no destination', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(downloads, 'Downloads');

    await app.pump(tester);

    expect(bar(tester), ['Home', 'More']);
    await app.stop(tester);
  });

  testWidgets('another profile shows only its own', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    final away = await app.addProfile('Away');
    await app.add(series, 'Shows', profileId: away);
    await app.pump(tester);
    await open(tester, 'Activity');

    await app.services.registry.switchTo(away);
    await tester.pumpAndSettle();

    expect(bar(tester), ['Home', 'Library', 'More']);
    expect(find.widgetWithText(AppBar, 'Away'), findsOneWidget);
    await open(tester, 'Library');
    expect(tabs(tester), ['Series']);
    await app.stop(tester);
  });

  testWidgets('a page of More that is no longer offered says so', (
    tester,
  ) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    final shows = await app.add(series, 'Shows');
    await app.pump(tester);
    await open(tester, 'More');
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not built yet'), findsOneWidget);

    await app.services.profiles.deleteInstance(shows);
    await tester.pumpAndSettle();

    expect(find.textContaining('No service in this profile'), findsOneWidget);
    await app.stop(tester);
  });

  for (final (permissions, expected) in [
    (<ServicePermission>{}, ['Browse']),
    ({ServicePermission.requestMovies}, ['Browse', 'Requests']),
    (
      {ServicePermission.manageRequests, ServicePermission.viewIssues},
      ['Browse', 'Requests', 'Issues'],
    ),
  ]) {
    testWidgets('Discover has $expected for $permissions', (tester) async {
      usePhone(tester);
      final requests = FakeModule(
        'requests',
        offers: {CapabilityKind.discovery, CapabilityKind.request},
        permissions: permissions,
      );
      final app = await TestApp.start(tester, modules: [requests]);
      await app.add(requests, 'Requests server');
      await app.pump(tester);

      expect(bar(tester), ['Home', 'Discover', 'More']);
      expect(find.byTooltip('Search'), findsOneWidget);
      await open(tester, 'Discover');

      expect(tabs(tester), expected);
      await app.stop(tester);
    });
  }

  testWidgets('search opens above the destinations', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.pump(tester);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Search'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('from 600 dp wide a rail replaces the bottom bar', (
    tester,
  ) async {
    usePhone(tester, const Size(599, 800));
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.pump(tester);
    expect(find.byType(NavigationRail), findsNothing);
    await open(tester, 'Library');

    tester.view.physicalSize = const Size(600, 400);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(4));
    // Still where it was.
    expect(rail.selectedIndex, 1);
    expect(tabs(tester), ['Movies']);
    await app.stop(tester);
  });

  for (final size in [const Size(360, 640), const Size(640, 360)]) {
    testWidgets('nothing overflows at 200% text on $size', (tester) async {
      usePhone(tester, size);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await TestApp.start(tester);
      await app.add(movies, 'Films');
      await app.add(series, 'Shows');
      await app.pump(tester);

      for (final destination in ['Library', 'Activity', 'More', 'Home']) {
        await tester.tap(find.text(destination).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: destination);
      }
      await app.stop(tester);
    });
  }
}
