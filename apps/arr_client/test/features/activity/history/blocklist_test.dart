import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../queue/support.dart';
import 'support.dart';

void main() {
  late ActivityModule module;

  setUp(() => module = ActivityModule());

  testWidgets('says why each release was blocked', (tester) async {
    useScreen(tester);
    module.of('Cellar').blocked = [
      [
        blocked(2, day: 4, reason: 'Manually marked\u202E as failed'),
        blocked(1),
      ],
    ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openBlocklist(tester);

    expect(find.widgetWithText(AppBar, 'Blocklist'), findsOneWidget);
    expect(
      find.text('Reason: Manually marked\u{fffd} as failed'),
      findsOneWidget,
    );
    // None is made up where the server gives none.
    expect(find.textContaining('Reason:'), findsOneWidget);
    expect(find.text('WEBDL-1080p'), findsNWidgets(2));
    expect(find.textContaining('March 4, 2026'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says that it is empty', (tester) async {
    useScreen(tester);
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openBlocklist(tester);

    expect(find.text('The blocklist is empty.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('offline, says why and reads again on retry', (tester) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..failure = const Unreachable()
      ..blocked = [
        [blocked(1)],
      ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openBlocklist(tester);
    expect(find.textContaining('The server did not answer.'), findsOneWidget);

    fake.failure = null;
    await tester.tap(find.text('Retry'));
    await step(tester);

    expect(find.text('Release 1'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('reads older entries on request', (tester) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..blocked = [
        [blocked(2, day: 2)],
        [blocked(1)],
      ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openBlocklist(tester);

    await tester.tap(find.text('Show older entries'));
    await step(tester);

    expect(find.text('Release 1'), findsOneWidget);
    expect(fake.blocklistReads, [1, 2]);
    await app.stop(tester);
  });

  testWidgets('removes one entry only once confirmed, then reads again', (
    tester,
  ) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..blocked = [
        [blocked(5, title: 'Blocked.Release')],
      ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openBlocklist(tester);

    await tester.tap(find.text('Remove from blocklist'));
    await step(tester);
    expect(find.text('Remove from the blocklist?'), findsOneWidget);
    expect(find.text('The server may grab this release again.'), findsOne);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Blocked.Release'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await step(tester);
    expect(fake.writes, isEmpty);

    final gate = fake.writeGate = Completer<void>();
    await tester.tap(find.text('Remove from blocklist'));
    await step(tester);
    await confirm(tester, 'Remove from blocklist');

    expect(fake.writes, ['unblock [5]']);
    expect(enabled(tester, 'Remove from blocklist'), [false]);
    expect(find.textContaining('accepted'), findsNothing);

    fake.blocked = [[]];
    gate.complete();
    await step(tester);

    expect(find.text('Cellar accepted the removal.'), findsOneWidget);
    expect(find.text('Blocked.Release'), findsNothing);
    expect(fake.blocklistReads, [1, 1]);
    await app.stop(tester);
  });

  testWidgets('removes several, one request to each service, once', (
    tester,
  ) async {
    useScreen(tester, const Size(400, 1600));
    final cellar = module.of('Cellar')
      ..blocked = [
        [blocked(1, day: 3), blocked(2, day: 2), blocked(3)],
      ];
    final attic = module.of('Attic')
      ..blocked = [
        [blocked(1, title: 'Other', day: 5)],
      ]
      ..answer = const Err(OutcomeUnknown());
    final (app, _) = await startWith(tester, module, ['Cellar', 'Attic']);
    await openBlocklist(tester);

    await tester.tap(find.text('Select'));
    await step(tester);
    for (final title in ['Other', 'Release 1', 'Release 2']) {
      await tester.tap(find.text(title));
      await tester.pump();
    }
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.text('Remove selected'));
    await step(tester);
    expect(find.text('Remove 3 entries from the blocklist?'), findsOneWidget);
    expect(find.textContaining('Other (Attic)'), findsOneWidget);
    expect(find.textContaining('Release 1 (Cellar)'), findsOneWidget);
    await confirm(tester, 'Remove 3 entries');
    await tester.pump(const Duration(minutes: 1));

    expect(cellar.writes, ['unblock [1, 2]']);
    expect(attic.writes, ['unblock [1]']);
    // The failure stays until dismissed; the success waits or passes.
    expect(
      find.textContaining('Attic: The change may or may not have reached'),
      findsOneWidget,
    );
    expect(cellar.blocklistReads, [1, 1]);
    expect(attic.blocklistReads, [1, 1]);
    // The selection is over.
    expect(find.text('Select'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('back leaves the selection first', (tester) async {
    useScreen(tester);
    module.of('Cellar').blocked = [
      [blocked(1)],
    ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openBlocklist(tester);
    await tester.longPress(find.text('Release 1'));
    await step(tester);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await step(tester);

    expect(find.text('1 selected'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Blocklist'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('nothing is removed on the strength of old entries', (
    tester,
  ) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..blocked = [
        [blocked(1)],
      ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openBlocklist(tester);

    fake.failure = const Unreachable();
    await tester.tap(find.byTooltip('Refresh the blocklist'));
    await step(tester);

    expect(enabled(tester, 'Remove from blocklist'), [false]);
    await app.stop(tester);
  });

  testWidgets('fits a narrow screen with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    useScreen(tester, const Size(320, 640));
    module.of('Cellar').blocked = [
      [
        blocked(
          1,
          title: 'A.Very.Long.Release.Name.Without.Any.Space' * 3,
          reason: 'It failed for a long reason. ' * 5,
        ),
      ],
      [],
    ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openBlocklist(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel(RegExp('^Remove from blocklist: A.Very.Long')),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.text('Select'));
    await step(tester);
    expect(tester.takeException(), isNull);
    handle.dispose();
    await app.stop(tester);
  });
}
