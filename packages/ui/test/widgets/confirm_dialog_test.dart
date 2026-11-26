import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'app.dart';

void main() {
  late Future<bool> answer;

  Future<void> open(
    WidgetTester tester, {
    double textScale = 1,
    Widget? options,
    bool destructive = true,
    String target = 'Alien (1979)',
  }) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => answer = showConfirmDialog(
              context,
              title: 'Delete movie?',
              target: target,
              consequence: 'It is removed from the server.',
              confirmLabel: 'Delete movie',
              options: options,
              destructive: destructive,
            ),
            child: const Text('Open'),
          ),
        ),
        textScale: textScale,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the target and the consequence', (tester) async {
    await open(tester, options: const Text('Delete files'));

    expect(find.text('Delete movie?'), findsOneWidget);
    expect(find.text('Alien (1979)'), findsOneWidget);
    expect(find.text('It is removed from the server.'), findsOneWidget);
    expect(find.text('Delete files'), findsOneWidget);
  });

  testWidgets('is true only when confirmed', (tester) async {
    await open(tester);
    await tester.tap(find.text('Delete movie'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);

    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);

    await open(tester);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await answer, isFalse);

    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await answer, isFalse);
  });

  testWidgets('marks only a destructive confirm in the error colour', (
    tester,
  ) async {
    Color? background() => tester
        .widget<FilledButton>(find.byType(FilledButton))
        .style
        ?.backgroundColor
        ?.resolve({});

    await open(tester);
    expect(background(), ArrTheme.light().colorScheme.error);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await open(tester, destructive: false);
    expect(background(), isNull);
  });

  testWidgets('keeps the consequence in sight above a long list of targets', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 740)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(
      tester,
      textScale: 2,
      target: [for (var i = 1; i <= 40; i++) 'Title $i'].join('\n'),
    );

    // Without any scrolling: whole, within what the dialog shows.
    final consequence = find.text('It is removed from the server.');
    final shown = tester.getRect(
      find
          .ancestor(
            of: consequence,
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    final rect = tester.getRect(consequence);
    expect(rect.top, greaterThanOrEqualTo(shown.top));
    expect(rect.bottom, lessThanOrEqualTo(shown.bottom));
    expect(consequence.hitTestable(), findsOneWidget);
    expect(find.text('Delete movie').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('works at 200% text on a small screen', (tester) async {
    useSmallScreen(tester);
    final semantics = tester.ensureSemantics();
    await open(
      tester,
      textScale: 2,
      options: CheckboxListTile(
        value: false,
        onChanged: (_) {},
        title: const Text('Delete files and exclude from import lists'),
      ),
    );

    expect(tester.takeException(), isNull);
    await expectAccessibleTargets(tester);
    await tester.tap(find.text('Delete movie'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
    semantics.dispose();
  });
}
