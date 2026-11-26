import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'app.dart';

void main() {
  late Completer<Result<void, ServiceFailure>> server;
  late int sent;
  late int refreshed;
  late int gone;
  Result<void, ServiceFailure>? returned;

  setUp(() {
    sent = refreshed = gone = 0;
    returned = null;
  });

  Widget button() => Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        returned = await runAction<void>(
          context,
          action: () {
            sent++;
            return server.future;
          },
          acceptedMessage: 'Search started',
          onRefresh: () => refreshed++,
          onGone: () => gone++,
        );
      },
      child: const Text('Search'),
    ),
  );

  Future<void> start(WidgetTester tester, {double textScale = 1}) async {
    // Made in the test body: its zone is the one the tester pumps.
    server = Completer();
    await tester.pumpWidget(testApp(button(), textScale: textScale));
    await tester.tap(find.text('Search'));
    await tester.pump();
  }

  Future<void> answer(
    WidgetTester tester,
    Result<void, ServiceFailure> result,
  ) async {
    server.complete(result);
    await tester.pumpAndSettle();
  }

  testWidgets('reports success only once the server accepts', (tester) async {
    await start(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(SnackBar), findsNothing);

    await answer(tester, const Ok(null));

    expect(find.text('Search started'), findsOneWidget);
    expect(returned, isA<Ok<void, ServiceFailure>>());
    expect((sent, refreshed, gone), (1, 0, 0));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failure is shown until dismissed and not retried', (
    tester,
  ) async {
    await start(tester);
    await answer(tester, const Err(Forbidden()));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('does not allow'), findsOneWidget);
    expect(find.text('Search started'), findsNothing);
    expect(returned, isA<Err<void, ServiceFailure>>());
    expect((sent, refreshed, gone), (1, 0, 0));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an unknown outcome refreshes without sending again', (
    tester,
  ) async {
    await start(tester);
    await answer(tester, const Err(OutcomeUnknown()));

    expect(find.textContaining('may or may not'), findsOneWidget);
    expect(find.text('Search started'), findsNothing);
    expect((sent, refreshed, gone), (1, 1, 0));
  });

  testWidgets('a gone item is reported and forgotten', (tester) async {
    await start(tester);
    await answer(tester, const Err(NotFound()));

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
    expect((sent, refreshed, gone), (1, 0, 1));
  });

  Future<void> again(
    WidgetTester tester,
    Result<void, ServiceFailure> result,
  ) async {
    server = Completer();
    await tester.tap(find.text('Search'));
    await answer(tester, result);
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  }

  testWidgets('later outcomes wait behind an unread failure', (tester) async {
    await start(tester);
    await answer(tester, const Err(OutcomeUnknown()));
    await again(tester, const Ok(null));
    await again(tester, const Err(Forbidden()));

    expect(find.textContaining('may or may not'), findsOneWidget);
    expect(find.text('Search started'), findsNothing);

    await dismiss(tester);
    expect(find.text('Search started'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not allow'), findsOneWidget);
    await dismiss(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final (name, result, text) in [
    ('success', const Ok<void, ServiceFailure>(null), 'Search started'),
    ('failure', const Err<void, ServiceFailure>(Forbidden()), 'does not allow'),
  ]) {
    testWidgets('a $name takes the place of a success', (tester) async {
      await start(tester);
      await answer(tester, const Ok(null));
      await again(tester, result);

      expect(find.textContaining(text), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      if (result is Ok) {
        // Not queued: nothing follows it.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      }
    });
  }

  testWidgets('a success replaces again once failures are dismissed', (
    tester,
  ) async {
    await start(tester);
    await answer(tester, const Err(Forbidden()));
    await dismiss(tester);
    await again(tester, const Ok(null));
    await again(tester, const Err(Conflict()));

    expect(find.textContaining('clashes'), findsOneWidget);
    expect(find.text('Search started'), findsNothing);
  });

  testWidgets('the message leaves the primary scroll controller alone', (
    tester,
  ) async {
    await start(tester);
    await answer(tester, const Ok(null));

    final context = tester.element(find.text('Search'));
    expect(PrimaryScrollController.of(context).positions, isEmpty);
  });

  testWidgets('reports after the screen has been left', (tester) async {
    await start(tester);
    await tester.pumpWidget(testApp(const Text('Elsewhere')));
    await answer(tester, const Err(OutcomeUnknown()));

    expect(find.text('Search'), findsNothing);
    expect(find.textContaining('may or may not'), findsOneWidget);
    expect(refreshed, 1);
  });

  testWidgets('a long message works at 200% text on a small screen', (
    tester,
  ) async {
    useSmallScreen(tester);
    final semantics = tester.ensureSemantics();
    await start(tester, textScale: 2);
    await answer(
      tester,
      Err(Validation(List.filled(20, 'The server did not like this value.'))),
    );

    expect(tester.takeException(), isNull);
    await expectAccessibleTargets(tester);
    expect(find.byIcon(Icons.close).hitTestable(), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a failure can be reworded', (tester) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => runAction<void>(
              context,
              action: () async => const Err(NotFound()),
              acceptedMessage: 'Accepted',
              describeFailure: (message) => 'Films: $message',
              onRefresh: () {},
            ),
            child: const Text('Send'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(
      find.text('Films: This item no longer exists on the server.'),
      findsOneWidget,
    );
  });
}
