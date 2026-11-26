import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../queue/support.dart';
import 'support.dart';

void main() {
  late ActivityModule module;

  setUp(() => module = ActivityModule());

  testWidgets('lists every instance newest first, with its name', (
    tester,
  ) async {
    useScreen(tester, const Size(400, 2000));
    module.of('Cellar').pages = [
      [grab(2, day: 8), grab(1, day: 2, type: HistoryEventType.imported)],
    ];
    module.of('Attic').pages = [
      [grab(1, title: 'Between', day: 5)],
    ];
    final (app, _) = await startWith(tester, module, ['Cellar', 'Attic']);
    await openHistoryTab(tester);

    final tops = [
      for (final title in ['Release 2', 'Between', 'Release 1'])
        tester.getTopLeft(find.text(title)).dy,
    ];
    expect(tops, [...tops]..sort());
    expect(find.text('Cellar'), findsNWidgets(2));
    expect(find.text('Attic'), findsOneWidget);
    // Only a grab can be marked.
    expect(find.text('Mark as failed'), findsNWidgets(2));
    await app.stop(tester);
  });

  testWidgets('older events take their place among the instances', (
    tester,
  ) async {
    useScreen(tester, const Size(400, 2000));
    module.of('Cellar').pages = [
      [grab(3, day: 9)],
      [grab(2, day: 3)],
    ];
    module.of('Attic').pages = [
      [grab(4, title: 'Long ago', day: 1)],
    ];
    final (app, _) = await startWith(tester, module, ['Cellar', 'Attic']);
    await openHistoryTab(tester);

    // Cellar may have events from after it, which are not read yet.
    expect(find.text('Long ago'), findsNothing);

    await tester.tap(find.text('Show older events'));
    await step(tester);

    expect(module.of('Cellar').reads, [1, 2]);
    expect(module.of('Attic').reads, [1]);
    expect(
      tester.getTopLeft(find.text('Release 2')).dy,
      lessThan(tester.getTopLeft(find.text('Long ago')).dy),
    );
    expect(find.text('Show older events'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('one instance that fails does not hide the others', (
    tester,
  ) async {
    useScreen(tester);
    module.of('Cellar').pages = [
      [grab(1)],
    ];
    module.of('Attic').failure = const Unreachable();
    final (app, _) = await startWith(tester, module, ['Cellar', 'Attic']);
    await openHistoryTab(tester);

    expect(find.text('Release 1'), findsOneWidget);
    expect(find.textContaining('The server did not answer.'), findsOneWidget);

    module.of('Attic')
      ..failure = null
      ..pages = [
        [grab(1, title: 'Found again', day: 2)],
      ];
    await tester.tap(find.text('Retry'));
    await step(tester);

    expect(find.text('Found again'), findsOneWidget);
    expect(find.textContaining('The server did not answer.'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('is read again on the way back to Activity', (tester) async {
    useScreen(tester);
    final fake = module.of('Cellar');
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);
    expect(fake.reads, [1]);

    await go(tester, 'Home');
    await go(tester, 'Activity');

    expect(fake.reads, [1, 1]);
    await app.stop(tester);
  });

  testWidgets('says that there is nothing', (tester) async {
    useScreen(tester);
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);

    expect(find.text('No history yet.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('marks a grab only once confirmed, then reads again', (
    tester,
  ) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..pages = [
        [
          grab(
            7,
            title: 'Bad.Release',
            downloadId: 'abc',
            kind: MediaKind.episode,
          ),
        ],
      ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);

    await tester.tap(find.text('Mark as failed'));
    await step(tester);
    expect(find.text('Mark this download as failed?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Bad.Release'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('adds the release to its blocklist'), findsOne);
    expect(
      find.textContaining('decide only whether it searches for another'),
      findsOneWidget,
    );
    expect(
      find.textContaining('The download is not removed or stopped'),
      findsOneWidget,
    );
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.textContaining('season pack'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await step(tester);
    expect(fake.writes, isEmpty);

    final gate = fake.writeGate = Completer<void>();
    await tester.tap(find.text('Mark as failed'));
    await step(tester);
    await confirm(tester, 'Mark as failed');

    expect(fake.writes, ['markFailed 7']);
    expect(enabled(tester, 'Mark as failed'), [false]);
    expect(find.textContaining('accepted'), findsNothing);
    expect(fake.reads, [1]);

    gate.complete();
    await step(tester);

    expect(
      find.text('Cellar accepted marking the download as failed.'),
      findsOneWidget,
    );
    expect(fake.writes, hasLength(1));
    expect(fake.reads, [1, 1]);
    expect(enabled(tester, 'Mark as failed'), [true]);
    await app.stop(tester);
  });

  testWidgets('a movie grab speaks of no season pack', (tester) async {
    useScreen(tester);
    module.of('Cellar').pages = [
      [grab(7, downloadId: 'abc', kind: MediaKind.movie)],
    ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);

    await tester.tap(find.text('Mark as failed'));
    await step(tester);

    expect(find.text('Mark this download as failed?'), findsOneWidget);
    expect(find.textContaining('season pack'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('an unknown outcome is said, not sent again, and read', (
    tester,
  ) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..pages = [
        [grab(7)],
      ]
      ..answer = const Err(OutcomeUnknown());
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);

    await tester.tap(find.text('Mark as failed'));
    await step(tester);
    // Without a download there is nothing else that goes with it.
    expect(find.textContaining('season pack'), findsNothing);
    await confirm(tester, 'Mark as failed');
    await tester.pump(const Duration(minutes: 1));

    expect(
      find.textContaining('Cellar: The change may or may not have reached'),
      findsOneWidget,
    );
    expect(fake.writes, ['markFailed 7']);
    expect(fake.reads, [1, 1]);
    await app.stop(tester);
  });

  testWidgets('what is still being sent is not offered on the way back', (
    tester,
  ) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..pages = [
        [grab(7)],
      ]
      ..writeGate = Completer<void>();
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);
    await tester.tap(find.text('Mark as failed'));
    await step(tester);
    await confirm(tester, 'Mark as failed');

    await tester.tap(find.widgetWithText(Tab, 'Queue'));
    await step(tester);
    await tester.tap(find.widgetWithText(Tab, 'History'));
    await step(tester);

    expect(enabled(tester, 'Mark as failed'), [false]);

    final reads = fake.reads.length;
    fake.writeGate!.complete();
    await step(tester);

    expect(fake.reads, hasLength(reads + 1));
    expect(enabled(tester, 'Mark as failed'), [true]);
    expect(fake.writes, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('nothing is marked on the strength of old events', (
    tester,
  ) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..pages = [
        [grab(7)],
      ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);

    fake.failure = const Unreachable();
    await tester.tap(find.byTooltip('Refresh the history'));
    await step(tester);

    expect(find.textContaining('Saved data from'), findsOneWidget);
    expect(enabled(tester, 'Mark as failed'), [false]);
    await app.stop(tester);
  });

  testWidgets('nothing is sent to a service edited meanwhile', (tester) async {
    useScreen(tester);
    final fake = module.of('Cellar')
      ..pages = [
        [grab(7)],
      ];
    final (app, ids) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);
    await tester.tap(find.text('Mark as failed'));
    await step(tester);

    await app.services.profiles.deleteInstance(ids.single);
    await app.services.registry.refresh();
    await step(tester);
    // The destination has gone, but the dialog is still above it.
    await confirm(tester, 'Mark as failed');

    expect(fake.writes, isEmpty);
    await app.stop(tester);
  });

  testWidgets('fits a narrow screen with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    useScreen(tester, const Size(320, 640));
    module.of('Cellar').pages = [
      [grab(1, title: 'A.Very.Long.Release.Name.Without.Any.Space' * 3)],
      [],
    ];
    final (app, _) = await startWith(tester, module, ['Cellar']);
    await openHistoryTab(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel(RegExp('^Mark as failed: A.Very.Long')),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.ensureVisible(find.text('Mark as failed'));
    await step(tester);
    await tester.tap(find.text('Mark as failed'));
    await step(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5));
    await step(tester);
    handle.dispose();
    await app.stop(tester);
  });
}
