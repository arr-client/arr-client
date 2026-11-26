import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'app.dart';

const unreachable =
    'The server did not answer. Check that it is running and that this device '
    'can reach its address.';
const gone = 'This item no longer exists on the server.';

Widget scaffold(
  ViewState<List<String>> state, {
  VoidCallback? onRetry,
  VoidCallback? onGone,
  Object itemId = 'alien',
  String? emptyMessage,
}) => StateScaffold<List<String>>(
  state: state,
  onRetry: onRetry ?? () {},
  itemId: itemId,
  onGone: onGone,
  isEmpty: (items) => items.isEmpty,
  emptyMessage: emptyMessage,
  builder: (context, items, {required isStale}) => ListView(
    children: [
      FilledButton(
        onPressed: isStale ? null : () {},
        child: const Text('Search'),
      ),
      for (final item in items) Text(item),
    ],
  ),
);

Staleness stale(Duration age, [ServiceFailure? failure]) =>
    Staleness(fetchedAt: DateTime.now().subtract(age), failure: failure);

bool searchEnabled(WidgetTester tester) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, 'Search'))
    .enabled;

void main() {
  testWidgets('loading shows progress that screen readers can name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(testApp(scaffold(const ViewLoading())));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('current data is shown without a notice', (tester) async {
    await tester.pumpWidget(testApp(scaffold(const ViewData(['Alien']))));

    expect(find.text('Alien'), findsOneWidget);
    expect(find.textContaining('Saved data'), findsNothing);
    expect(searchEnabled(tester), isTrue);
  });

  testWidgets('empty data says so, with the text of the caller if given', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(scaffold(const ViewData([]))));
    expect(find.text('Nothing to show'), findsOneWidget);

    await tester.pumpWidget(
      testApp(scaffold(const ViewData([]), emptyMessage: 'No movies')),
    );
    expect(find.text('No movies'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
  });

  testWidgets('an error says what happened and retries on request', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      testApp(
        scaffold(const ViewError(Unreachable()), onRetry: () => retries++),
      ),
    );

    expect(find.text(unreachable), findsOneWidget);
    expect(retries, 0);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('stale data is shown with its age, reason and a retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      testApp(
        scaffold(
          ViewData(const [
            'Alien',
          ], staleness: stale(const Duration(hours: 3), const Unreachable())),
          onRetry: () => retries++,
        ),
      ),
    );

    expect(find.text('Saved data from 3 hours ago'), findsOneWidget);
    expect(find.text(unreachable), findsOneWidget);
    expect(find.text('Alien'), findsOneWidget);
    expect(searchEnabled(tester), isFalse);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('stale data being refreshed shows progress and no retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        scaffold(
          ViewData(const ['Alien'], staleness: stale(const Duration(days: 1))),
        ),
      ),
    );

    expect(find.text('Saved data from 1 day ago'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(searchEnabled(tester), isFalse);
  });

  testWidgets('the age is worded by its size', (tester) async {
    for (final (age, text) in [
      (Duration.zero, 'Saved data from less than a minute ago'),
      // A clock that was set back.
      (const Duration(hours: -1), 'Saved data from less than a minute ago'),
      (const Duration(minutes: 1), 'Saved data from 1 minute ago'),
      (const Duration(minutes: 59), 'Saved data from 59 minutes ago'),
      (const Duration(days: 1200), 'Saved data from 1,200 days ago'),
    ]) {
      await tester.pumpWidget(
        testApp(scaffold(ViewData(const [], staleness: stale(age)))),
      );
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('empty saved data is both empty and stale', (tester) async {
    await tester.pumpWidget(
      testApp(
        scaffold(
          ViewData(const [], staleness: stale(Duration.zero)),
          emptyMessage: 'No movies',
        ),
      ),
    );

    expect(find.textContaining('Saved data'), findsOneWidget);
    expect(find.text('No movies'), findsOneWidget);
  });

  testWidgets('content keeps its state when data turns stale', (tester) async {
    final items = [for (var i = 0; i < 100; i++) 'Item $i'];
    final list = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.pumpWidget(testApp(scaffold(ViewData(items))));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    final before = tester.state<ScrollableState>(list);
    final offset = before.position.pixels;
    expect(offset, greaterThan(0));

    await tester.pumpWidget(
      testApp(
        scaffold(
          ViewData(items, staleness: stale(Duration.zero, const Unreachable())),
        ),
      ),
    );

    final after = tester.state<ScrollableState>(list);
    expect(after, same(before));
    expect(after.position.pixels, offset);
  });

  for (final (name, state) in <(String, ViewState<List<String>>)>[
    ('a failed load', const ViewError(NotFound())),
    (
      'a failed refresh of saved data',
      ViewData(const [
        'Alien',
      ], staleness: stale(Duration.zero, const NotFound())),
    ),
  ]) {
    testWidgets('an item gone on $name is reported once', (tester) async {
      var forgotten = 0;
      Widget app() => testApp(scaffold(state, onGone: () => forgotten++));
      await tester.pumpWidget(app());
      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text(gone), findsOneWidget);
      expect(find.text('Alien'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      // The first screen has nowhere to go back to.
      expect(find.text('Go back'), findsNothing);
      expect(forgotten, 1);
    });
  }

  testWidgets('each gone item shown in the same place is reported', (
    tester,
  ) async {
    final forgotten = <int>[];
    Future<void> show(int id) async {
      await tester.pumpWidget(
        testApp(
          scaffold(
            const ViewError(NotFound()),
            // A new but equal object on each build, as an ItemRef may be.
            itemId: ItemRef(
              instanceId: 'a',
              kind: MediaKind.movie,
              remoteId: id,
            ),
            onGone: () => forgotten.add(id),
          ),
        ),
      );
      await tester.pump();
    }

    await show(1);
    await show(1);
    await show(2);
    await show(2);

    expect(forgotten, [1, 2]);
  });

  testWidgets('a gone item offers the way back', (tester) async {
    await tester.pumpWidget(testApp(const Text('List')));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                Scaffold(body: scaffold(const ViewError(NotFound()))),
          ),
        )
        .ignore();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(find.text('List'), findsOneWidget);
    expect(find.text(gone), findsNothing);
  });

  testWidgets('works at 200% text on a small screen', (tester) async {
    useSmallScreen(tester);
    final semantics = tester.ensureSemantics();
    const failure = Validation([
      'A long message from the server about the first value that was sent.',
      'A long message from the server about the second value that was sent.',
      'A long message from the server about the third value that was sent.',
    ]);
    for (final state in <ViewState<List<String>>>[
      const ViewError(failure),
      const ViewData([]),
      const ViewError(NotFound()),
      ViewData(const ['Alien'], staleness: stale(Duration.zero, failure)),
    ]) {
      await tester.pumpWidget(testApp(scaffold(state), textScale: 2));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await expectAccessibleTargets(tester);
    }
    // The content keeps room below a tall notice, and the retry can be reached.
    expect(find.text('Search').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('Retry'));
    await tester.pump();
    expect(find.text('Retry').hitTestable(), findsOneWidget);
    semantics.dispose();
  });
}
