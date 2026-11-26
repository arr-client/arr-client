/// Home: the status of each service and links to what they provide
/// (contracts/navigation.md).
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation_test.dart' show bar, usePhone;
import '../../app/support.dart';

/// A row of Home.
Finder _row(String title) => find.widgetWithText(ListTile, title);

Finder _within(String row, String text) =>
    find.descendant(of: _row(row), matching: find.text(text));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the status of each service, in their order', (
    tester,
  ) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.add(subtitles, 'Subs');
    await app.pump(tester);
    await settle(tester);

    expect(_within('Films', 'Connected to movies 1'), findsOneWidget);
    expect(_within('Subs', 'Connected to subtitles 1'), findsOneWidget);
    expect(
      tester.getTopLeft(_row('Films')).dy,
      lessThan(tester.getTopLeft(_row('Subs')).dy),
    );
    await app.stop(tester);
  });

  testWidgets('says why a service cannot be reached, and retries', (
    tester,
  ) async {
    usePhone(tester);
    final module = FakeModule('movies', offers: movies.offers)
      ..failure = const Unreachable();
    final app = await TestApp.start(tester, modules: [module]);
    await app.add(module, 'Films');
    await app.pump(tester);
    await settle(tester);

    final retry = find.descendant(
      of: _row('Films'),
      matching: find.widgetWithText(TextButton, 'Retry'),
    );
    expect(retry, findsOneWidget);
    expect(_within('Films', 'Connected to movies 1'), findsNothing);

    module.failure = null;
    await _tap(tester, retry);
    await settle(tester);
    await tester.pumpAndSettle();

    expect(_within('Films', 'Connected to movies 1'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('leaves a disabled service out', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.add(series, 'Shows', enabled: false);
    await app.pump(tester);

    expect(_row('Films'), findsOneWidget);
    expect(find.text('Shows'), findsNothing);
    expect(find.textContaining('disabled'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('is not blank when every service is disabled', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films', enabled: false);
    await app.pump(tester);

    expect(
      find.text('All services in this profile are disabled.'),
      findsOneWidget,
    );
    expect(find.text('Go to'), findsNothing);
    await _tap(tester, find.text('Manage services'));
    expect(find.widgetWithText(AppBar, 'Services'), findsOneWidget);
    expect(find.text('Films'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says that a service of an unknown type is not supported', (
    tester,
  ) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    final other = FakeModule('other', offers: {CapabilityKind.library});
    // Saved by a version that had the module.
    final profiles = ProfileRepository(
      database: app.services.database,
      secrets: MemorySecrets(),
      log: app.services.log,
      preferences: app.services.preferences,
      modules: [other],
    );
    await profiles.addInstance(
      await app.activeProfile,
      InstanceDraft(
        name: 'Shows',
        serviceType: other.id,
        url: Uri.parse('http://server.invalid/'),
        authKind: AuthKind.apiKey,
      ),
    );
    await app.pump(tester);

    expect(_within('Shows', 'Not supported by this version'), findsOneWidget);
    expect(tester.widget<ListTile>(_row('Shows')).onTap, isNull);
    await app.stop(tester);
  });

  testWidgets('opens the form of a service', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.pump(tester);

    await _tap(tester, find.text('Films'));

    expect(find.widgetWithText(TextFormField, 'Films'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('links only to the areas that are configured', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.pump(tester);

    expect(find.text('Go to'), findsOneWidget);
    expect(_row('Library'), findsOneWidget);
    expect(_row('Activity'), findsOneWidget);
    expect(_row('Discover'), findsNothing);

    await _tap(tester, _row('Activity'));
    expect(find.widgetWithText(AppBar, 'Activity'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('is only the status for a subtitle service', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(subtitles, 'Subs');
    await app.pump(tester);

    expect(bar(tester), ['Home', 'More']);
    expect(_row('Subs'), findsOneWidget);
    expect(find.text('Go to'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('shows only the services of the active profile', (tester) async {
    usePhone(tester);
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    final away = await app.addProfile('Away');
    await app.add(series, 'Shows', profileId: away);
    await app.pump(tester);
    expect(find.text('Shows'), findsNothing);

    await app.services.registry.switchTo(away);
    await tester.pumpAndSettle();
    await settle(tester);

    expect(_row('Shows'), findsOneWidget);
    expect(find.text('Films'), findsNothing);
    expect(_row('Activity'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('has headings and a wider margin on a wide screen', (
    tester,
  ) async {
    usePhone(tester, const Size(900, 800));
    final semantics = tester.ensureSemantics();
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.pump(tester);

    for (final heading in ['Services', 'Go to']) {
      expect(
        tester.getSemantics(find.text(heading)),
        isSemantics(label: heading, isHeader: true),
      );
    }
    final list = tester.getTopLeft(find.byType(CustomScrollView)).dx;
    expect(tester.getTopLeft(find.text('Services')).dx - list, 24);
    expect(tester.getTopLeft(find.byIcon(Icons.dns)).dx - list, 24);
    semantics.dispose();
    await app.stop(tester);
  });

  testWidgets('each service is a thing of its own to a screen reader', (
    tester,
  ) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.add(subtitles, 'Subs');
    await app.pump(tester);
    await settle(tester);

    expect(
      tester.getSemantics(find.text('Films')),
      isSemantics(label: 'Films\nConnected to movies 1', isButton: true),
    );
    semantics.dispose();
    await app.stop(tester);
  });

  testWidgets('fits large text on a small phone', (tester) async {
    usePhone(tester, const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final module = FakeModule('movies', offers: movies.offers)
      ..failure = const Unreachable();
    final app = await TestApp.start(tester, modules: [module]);
    await app.add(module, 'A film server with a rather long name');
    await app.pump(tester);
    await settle(tester);

    expect(find.text('A film server with a rather long name'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.scrollUntilVisible(
      _row('Activity'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
    await app.stop(tester);
  });
}
