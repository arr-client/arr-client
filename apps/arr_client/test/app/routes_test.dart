/// Instance-scoped routes and the shared flows (contracts/navigation.md,
/// contracts/module-contract.md "Navigation intents").
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'navigation_test.dart' show open, usePhone;
import 'support.dart';

/// Opens [location] above what is shown, as a screen or a notification would.
Future<void> push(WidgetTester tester, TestApp app, String location) async {
  app.services.navigator.router!.push<void>(location).ignore();
  await tester.pumpAndSettle();
}

String item(String instanceId) => ModuleRoute(
  instanceId: instanceId,
  path: 'movies/items/7',
  query: {'from': 'queue'},
).location;

void main() {
  late TestApp app;

  Future<String> start(WidgetTester tester, {bool enabled = true}) async {
    usePhone(tester);
    app = await TestApp.start(tester);
    final id = await app.add(movies, 'Films', enabled: enabled);
    await app.pump(tester);
    return id;
  }

  testWidgets('a module route shows the module screen', (tester) async {
    final films = await start(tester);

    await push(tester, app, item(films));

    expect(find.text('Films item 7 queue'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('removing the instance explains instead', (tester) async {
    final films = await start(tester);
    await push(tester, app, item(films));

    await app.services.profiles.deleteInstance(films);
    await tester.pumpAndSettle();

    expect(find.text('This service has been removed.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a disabled instance is explained', (tester) async {
    final films = await start(tester, enabled: false);

    await push(tester, app, item(films));

    expect(find.textContaining('Films is disabled'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('an instance of another profile offers to switch', (
    tester,
  ) async {
    await start(tester);
    final away = await app.addProfile('Away');
    final other = await app.add(movies, 'Cabin', profileId: away);

    await push(tester, app, item(other));
    expect(find.text('Cabin belongs to the profile Away.'), findsOneWidget);
    // Nothing is switched without being asked.
    expect(await app.activeProfile, isNot(away));

    await tester.tap(find.text('Switch to Away'));
    await tester.pumpAndSettle();

    expect(await app.activeProfile, away);
    expect(find.text('Cabin item 7 queue'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a destination that goes does not close the page above it', (
    tester,
  ) async {
    await start(tester);
    final away = await app.addProfile('Away');
    final other = await app.add(downloads, 'Cabin', profileId: away);
    await open(tester, 'Library');
    await push(tester, app, '/instances/$other/history');

    // The new profile has no library.
    await tester.tap(find.text('Switch to Away'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'History'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Away'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('the shared flows open and complete when closed', (tester) async {
    final films = await start(tester);
    final ref = ItemRef(instanceId: films, kind: MediaKind.movie, remoteId: 7);
    final navigator = app.services.registry.scope!
        .instance(films)!
        .context
        .navigator;

    // The edit sheet and the delete dialog lie over the screen that asked.
    for (final (flow, title) in <(Future<void> Function(), String)>[
      (() => navigator.openEdit(ref), 'Edit'),
      (() => navigator.openDelete(ref), 'Delete movie?'),
    ]) {
      var done = false;
      flow().then((_) => done = true).ignore();
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(done, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(done, isTrue, reason: title);
    }

    for (final (flow, title) in <(Future<void> Function(), String)>[
      (() => navigator.openReleases(MediaTarget(ref)), 'Releases'),
      (() => navigator.openHistory(ref), 'History'),
      (
        () => navigator.openAdd(
          const AddCandidate(
            kind: MediaKind.movie,
            title: 'A film',
            externalIds: ExternalIds(),
          ),
        ),
        'Add',
      ),
    ]) {
      var done = false;
      flow().then((_) => done = true).ignore();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, title), findsOneWidget);
      expect(done, isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(done, isTrue, reason: title);
    }
    await app.stop(tester);
  });

  testWidgets('More reaches a module screen by the capability route', (
    tester,
  ) async {
    usePhone(tester);
    app = await TestApp.start(tester);
    await app.add(subtitles, 'Subs');
    await app.pump(tester);
    await open(tester, 'More');
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Subs'));
    await tester.pumpAndSettle();

    // The fake has no screen at `subtitles/browse`, which is said plainly.
    expect(find.text('This page does not exist.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('unknown pages are explained and lead Home', (tester) async {
    final films = await start(tester);

    for (final location in [
      '/nowhere',
      '/instances/$films',
      '/instances/$films/movies/nothing',
      // Another module's screen for this instance.
      '/instances/$films/series/items/1',
    ]) {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
      await tester.pumpAndSettle();
      expect(
        find.text('This page does not exist.'),
        findsOneWidget,
        reason: location,
      );
      await tester.tap(find.text('Go to Home'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    }
    await app.stop(tester);
  });
}
