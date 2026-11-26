/// The list of services (spec story 1).
library;

import 'package:core/core.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/support.dart';

void usePhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(360, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A running app showing the list, with the services [names] in it.
Future<(TestApp, List<String>)> openList(
  WidgetTester tester, [
  List<String> names = const [],
]) async {
  usePhone(tester);
  final app = await TestApp.start(tester);
  final ids = [for (final name in names) await app.add(movies, name)];
  await app.pump(tester);
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Services'));
  await tester.pumpAndSettle();
  return (app, ids);
}

Future<void> choose(WidgetTester tester, String name, String entry) async {
  await tester.tap(find.byTooltip('Options for $name'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

Future<List<Instance>> saved(TestApp app) async =>
    app.services.profiles.instances(await app.activeProfile);

Future<List<String>> savedNames(TestApp app) async => [
  for (final instance in await saved(app)) instance.name,
];

/// The names in the order they are shown.
List<String> shown(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
    (tile.title! as Text).data!,
];

void main() {
  testWidgets('says when the profile has no service, and offers to add one', (
    tester,
  ) async {
    final (app, _) = await openList(tester);

    expect(find.text('This profile has no services.'), findsOneWidget);
    await tester.tap(find.text('Add service'));
    await tester.pumpAndSettle();

    // The picker of the onboarding feature.
    expect(find.widgetWithText(AppBar, 'Add service'), findsOneWidget);
    expect(find.text('movies'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('lists every service of the active profile, disabled ones too', (
    tester,
  ) async {
    final (app, _) = await openList(tester, ['Films']);
    await app.add(series, 'Shows', enabled: false);
    await app.add(movies, 'Elsewhere', profileId: await app.addProfile('Away'));
    await tester.pumpAndSettle();

    expect(shown(tester), ['Films', 'Shows']);
    expect(find.text('http://server.invalid/Films'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('opens the edit form by tap or menu, for a disabled one too', (
    tester,
  ) async {
    final (app, _) = await openList(tester, ['Films']);
    await app.add(series, 'Shows', enabled: false);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Edit Films'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await choose(tester, 'Shows', 'Edit');
    expect(find.widgetWithText(AppBar, 'Edit Shows'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('renames, refusing a taken or empty name', (tester) async {
    final (app, ids) = await openList(tester, ['Films', 'Shows']);
    final key = app.services.profiles.credential(ids.first);

    await choose(tester, 'Films', 'Rename');
    await tester.enterText(find.byType(TextField), 'shows');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Another service in this profile has this name.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Enter 1 to 40 characters.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' Cinema ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(shown(tester), ['Cinema', 'Shows']);
    expect(await savedNames(app), ['Cinema', 'Shows']);
    expect(
      (await app.services.profiles.credential(ids.first))?.apiKey,
      (await key)?.apiKey,
    );
    expect((await saved(app)).first.lastProbe, isNotNull);
    await app.stop(tester);
  });

  testWidgets('disables and enables, keeping the settings', (tester) async {
    final (app, ids) = await openList(tester, ['Films']);

    await choose(tester, 'Films', 'Disable');

    expect(find.text('Disabled'), findsOneWidget);
    expect((await saved(app)).single.enabled, isFalse);
    expect(app.services.registry.scope!.instance(ids.single), isNull);
    expect(await app.services.profiles.credential(ids.single), isNotNull);
    // Nothing offers movies any more.
    expect(find.text('Library'), findsNothing);

    await choose(tester, 'Films', 'Enable');

    expect(find.text('Disabled'), findsNothing);
    expect(app.services.registry.scope!.instance(ids.single), isNotNull);
    expect(find.text('Library'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('removes only after confirming, with secrets and cache', (
    tester,
  ) async {
    final (app, ids) = await openList(tester, ['Films', 'Shows']);
    final cache = app.services.cache.scope(ids.first);
    await cache.replace(MediaKind.movie, const []);

    await choose(tester, 'Films', 'Remove');
    expect(find.text('Remove service?'), findsOneWidget);
    expect(find.textContaining('the profile Default'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await savedNames(app), ['Films', 'Shows']);
    expect(await app.services.profiles.credential(ids.first), isNotNull);

    await choose(tester, 'Films', 'Remove');
    await tester.tap(find.text('Remove service'));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(shown(tester), ['Shows']);
    expect(await savedNames(app), ['Shows']);
    expect(await app.services.profiles.credential(ids.first), isNull);
    expect(await cache.read(MediaKind.movie), isNull);
    expect(app.services.registry.scope!.instance(ids.first), isNull);
    await app.stop(tester);
  });

  testWidgets('reorders by the menu', (tester) async {
    final (app, _) = await openList(tester, ['A', 'B', 'C']);

    await tester.tap(find.byTooltip('Options for A'));
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsNothing);
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(shown(tester), ['B', 'A', 'C']);

    await choose(tester, 'C', 'Move up');

    expect(shown(tester), ['B', 'C', 'A']);
    expect(await savedNames(app), ['B', 'C', 'A']);
    await app.stop(tester);
  });

  testWidgets('a move chosen after the list changed stays within it', (
    tester,
  ) async {
    final (app, ids) = await openList(tester, ['A', 'B', 'C']);

    // C goes while the menu of B offers to move below it.
    await tester.tap(find.byTooltip('Options for B'));
    await tester.pumpAndSettle();
    await app.services.profiles.deleteInstance(ids[2]);
    await settle(tester);
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(shown(tester), ['A', 'B']);

    // A goes while the menu of B offers to move above it.
    await tester.tap(find.byTooltip('Options for B'));
    await tester.pumpAndSettle();
    await app.services.profiles.deleteInstance(ids[0]);
    await settle(tester);
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await savedNames(app), ['B']);
    await app.stop(tester);
  });

  testWidgets('a move follows its service if the order changed', (
    tester,
  ) async {
    final (app, ids) = await openList(tester, ['A', 'B', 'C']);

    await tester.tap(find.byTooltip('Options for B'));
    await tester.pumpAndSettle();
    await app.services.profiles.reorderInstances(await app.activeProfile, [
      ids[0],
      ids[2],
      ids[1],
    ]);
    await settle(tester);
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();

    expect(await savedNames(app), ['A', 'B', 'C']);
    await app.stop(tester);
  });

  testWidgets('reorders by dragging the handle', (tester) async {
    final (app, _) = await openList(tester, ['A', 'B', 'C']);
    final row =
        tester.getTopLeft(find.text('B')).dy -
        tester.getTopLeft(find.text('A')).dy;

    final drag = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.drag_handle).first),
    );
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(Offset(0, row / 4));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await drag.up();
    await tester.pumpAndSettle();

    expect(shown(tester), ['B', 'C', 'A']);
    expect(await savedNames(app), ['B', 'C', 'A']);
    await app.stop(tester);
  });

  testWidgets('offers screen readers the moves and names each menu', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (app, _) = await openList(tester, ['A', 'B']);

    final labels = [
      for (final action
          in tester
              .getSemantics(find.text('A'))
              .getSemanticsData()
              .customSemanticsActionIds!)
        CustomSemanticsAction.getAction(action)!.label,
    ];
    expect(labels, contains('Move down'));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
    await app.stop(tester);
  });

  testWidgets('one service cannot be moved', (tester) async {
    final (app, _) = await openList(tester, ['A']);

    expect(find.byIcon(Icons.drag_handle), findsNothing);
    await tester.tap(find.byTooltip('Options for A'));
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsNothing);
    expect(find.text('Move down'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await app.stop(tester);
  });

  testWidgets('a type this version lacks can only be moved or removed', (
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
        name: 'Old',
        serviceType: other.id,
        url: Uri.parse('http://server.invalid/'),
        authKind: AuthKind.apiKey,
      ),
    );
    await app.pump(tester);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    expect(find.text('Not supported by this version'), findsOneWidget);
    await tester.tap(find.byTooltip('Options for Old'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Rename'), findsNothing);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove service'));
    await tester.pumpAndSettle();

    expect(await savedNames(app), isEmpty);
    await app.stop(tester);
  });

  testWidgets('says when a change cannot be saved', (tester) async {
    final (app, _) = await openList(tester, ['A', 'B']);
    await app.services.database.customStatement(
      'CREATE TRIGGER refuse BEFORE UPDATE ON instances '
      "BEGIN SELECT RAISE(ABORT, 'refused'); END",
    );

    await choose(tester, 'A', 'Move down');

    expect(
      find.text('The change could not be saved. Try again.'),
      findsOneWidget,
    );
    expect(shown(tester), ['A', 'B']);
    await app.stop(tester);
  });

  testWidgets('fits at twice the text size, dialogs included', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final (app, _) = await openList(tester, [
      'B',
      'A service with the longest name it may',
    ]);
    // The second row starts below the first, which wraps its address.
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.textContaining('longest name'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byTooltip('Options for B'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await choose(tester, 'B', 'Rename');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await choose(tester, 'B', 'Remove');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await app.stop(tester);
  });
}
