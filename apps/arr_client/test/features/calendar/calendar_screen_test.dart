/// The agenda, the month and the filter (spec story 6, scenarios 1 and 4).
/// CI runs this in zones east and west of UTC as well.
library;

import 'dart:async';

import 'package:arr_client/features/calendar/calendar_screen.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'support.dart';

// A Thursday.
final noon = DateTime(2026, 11, 26, 12);

/// The titles of the rows, from the top.
List<String> titles(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
    (tile.title! as Text).data!,
];

double top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(Tab, name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('releases of all services are merged by the local day', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    // Instants in UTC, as episodes are: either side of the local midnight, so
    // that for any zone away from UTC one of them is another day in UTC.
    calendar
      ..release(
        'Shows',
        'Late tonight',
        DateTime(2026, 11, 26, 23, 30).toUtc(),
        kind: CalendarDateKind.airDate,
      )
      ..release(
        'Shows',
        'Just after midnight',
        DateTime(2026, 11, 27, 0, 30).toUtc(),
        kind: CalendarDateKind.airDate,
        id: 2,
      )
      // Local midnights, as movie releases are.
      ..release('Films', 'Film of today', DateTime(2026, 11, 26))
      ..release('Films', 'Film of tomorrow', DateTime(2026, 11, 27), id: 2);

    await calendar.pump(tester);

    expect(titles(tester), [
      'Film of today',
      'Late tonight',
      'Film of tomorrow',
      'Just after midnight',
    ]);
    const today = 'Today, Thursday, November 26, 2026';
    const tomorrow = 'Tomorrow, Friday, November 27, 2026';
    expect(top(tester, today), lessThan(top(tester, 'Film of today')));
    expect(top(tester, 'Late tonight'), lessThan(top(tester, tomorrow)));
    expect(top(tester, tomorrow), lessThan(top(tester, 'Film of tomorrow')));
    expect(find.textContaining('11:30 PM · Airs · Shows'), findsOneWidget);
    expect(find.textContaining('12:30 AM · Airs · Shows'), findsOneWidget);
    // A day-long date has no time.
    expect(find.text('Digital release · Films'), findsNWidgets(2));
    expect(find.text('Missing'), findsNWidgets(4));
    await calendar.stop(tester);
  });

  testWidgets('releases of one moment keep the order of the services', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    final date = DateTime(2026, 11, 28);
    calendar
      ..release('Films', 'First film', date)
      ..release('Films', 'Second film', date, id: 2)
      ..release('Shows', 'Episode', date);
    // The first service answers last.
    final held = Completer<void>();
    calendar.server('Films').held = held;

    await calendar.pump(tester, settle: false);
    expect(titles(tester), ['Episode']);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    held.complete();
    await tester.pumpAndSettle();
    expect(titles(tester), ['First film', 'Second film', 'Episode']);
    await calendar.stop(tester);
  });

  testWidgets('a day without releases says so', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.release('Films', 'Next week', DateTime(2026, 12, 3));

    await calendar.pump(tester);

    expect(find.text('Today, Thursday, November 26, 2026'), findsOneWidget);
    expect(find.text('No releases today.'), findsOneWidget);
    expect(find.text('Thursday, December 3, 2026'), findsOneWidget);
    expect(find.textContaining('following'), findsNothing);
    await calendar.stop(tester);
  });

  testWidgets('an empty agenda says how far it looked, and looks further', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.release('Films', 'Far off', DateTime(2027, 1, 5));

    await calendar.pump(tester);
    expect(find.text('No releases in the following 29 days.'), findsOneWidget);
    expect(calendar.server('Films').ranges.last, (
      DateTime(2026, 11, 26),
      DateTime(2026, 12, 26),
    ));

    // What is listed stays while the later days are read.
    final held = Completer<void>();
    calendar.server('Films').held = held;
    await tester.tap(find.text('Show later days'));
    await tester.pump();
    expect(find.text('Show later days'), findsOneWidget);
    expect(find.textContaining('following'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    held.complete();
    await tester.pumpAndSettle();

    expect(find.text('Far off'), findsOneWidget);
    expect(calendar.server('Films').ranges.last, (
      DateTime(2026, 11, 26),
      DateTime(2027, 1, 25),
    ));
    await calendar.stop(tester);
  });

  testWidgets('one failing service does not hide the others', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.release('Shows', 'Episode', DateTime(2026, 11, 27));
    calendar.server('Films').failure = const Unreachable();

    await calendar.pump(tester);

    expect(find.text('Episode'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsOneWidget);
    // Not a claim that there is nothing today.
    expect(
      find.text('No releases from the services that answered.'),
      findsOneWidget,
    );
    expect(find.text('No releases today.'), findsNothing);

    calendar.server('Films').failure = null;
    calendar.release('Films', 'Film', DateTime(2026, 11, 26));
    final shows = calendar.server('Shows').ranges.length;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(titles(tester), ['Film', 'Episode']);
    expect(find.text('Retry'), findsNothing);
    // Only the one that failed is asked again.
    expect(calendar.server('Shows').ranges, hasLength(shows));
    await calendar.stop(tester);
  });

  testWidgets('when every service fails nothing is claimed', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.server('Films').failure = const Unreachable();
    calendar.server('Shows').failure = const ServerError(statusCode: 500);

    await calendar.pump(tester);

    expect(find.text('Retry'), findsNWidgets(2));
    expect(find.textContaining('No releases'), findsNothing);
    await calendar.stop(tester);
  });

  testWidgets('a failed refresh keeps what was loaded and says so', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.release('Films', 'Film', DateTime(2026, 11, 26));
    await calendar.pump(tester);

    calendar.server('Films').failure = const Unreachable();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Film'), findsOneWidget);
    // Its age, which unlike a time of day also says how many days ago.
    expect(find.byType(StaleNotice), findsOneWidget);
    expect(find.textContaining('Saved data from'), findsOneWidget);
    await calendar.stop(tester);
  });

  testWidgets('a change of connection does not read again, one of the '
      'services does', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar
      ..release('Films', 'Film', DateTime(2026, 11, 26))
      ..release('Shows', 'Episode', DateTime(2026, 11, 26));
    await calendar.pump(tester);
    final reads = calendar.server('Films').ranges.length;

    calendar.app.services.registry.resetConnections();
    await tester.pumpAndSettle();
    expect(calendar.server('Films').ranges, hasLength(reads));

    await calendar.app.services.profiles.deleteInstance(calendar.ids['Shows']!);
    await calendar.app.services.registry.refresh();
    await tester.pumpAndSettle();
    expect(titles(tester), ['Film']);
    expect(find.byType(FilterChip), findsNothing);
    await calendar.stop(tester);
  });

  testWidgets('the filter applies to every view', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar
      ..release('Films', 'Film', DateTime(2026, 11, 26))
      ..release('Shows', 'Episode', DateTime(2026, 11, 26))
      ..imported('Films', 'Imported film', DateTime(2026, 11, 26, 9))
      ..imported('Shows', 'Imported episode', DateTime(2026, 11, 26, 10));
    await calendar.pump(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Films'));
    await tester.pumpAndSettle();
    expect(titles(tester), ['Episode']);

    await tab(tester, 'Month');
    expect(titles(tester), ['Episode']);
    await tab(tester, 'Downloaded');
    expect(titles(tester), ['Imported episode']);

    await tester.tap(find.widgetWithText(FilterChip, 'Shows'));
    await tester.pumpAndSettle();
    expect(titles(tester), isEmpty);
    expect(find.textContaining('All services are hidden'), findsOneWidget);
    await calendar.stop(tester);
  });

  testWidgets('with one service there is nothing to filter or to name', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(
      tester,
      now: noon,
      names: ['Films'],
    );
    calendar.release('Films', 'Film', DateTime(2026, 11, 26));

    await calendar.pump(tester);

    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Digital release'), findsOneWidget);
    await calendar.stop(tester);
  });

  testWidgets('the month counts releases and lists those of a day', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar
      ..release('Films', 'Film', DateTime(2026, 11, 30))
      ..release(
        'Shows',
        'Episode',
        DateTime(2026, 11, 30, 23, 30).toUtc(),
        kind: CalendarDateKind.airDate,
      )
      ..release('Films', 'Of December', DateTime(2026, 12, 4), id: 2);

    await calendar.pump(tester, tab: CalendarTab.month);

    expect(find.text('November 2026'), findsOneWidget);
    expect(calendar.server('Films').ranges.last, (
      DateTime(2026, 11),
      DateTime(2026, 12),
    ));
    expect(find.text('No releases on this day.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Thursday, November 26, 2026, Today, no releases'),
      findsOneWidget,
    );

    await tester.tap(
      find.bySemanticsLabel('Monday, November 30, 2026, 2 releases'),
    );
    await tester.pumpAndSettle();
    expect(titles(tester), ['Film', 'Episode']);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
    await tester.tap(
      find.bySemanticsLabel('Friday, December 4, 2026, 1 release'),
    );
    await tester.pumpAndSettle();
    expect(titles(tester), ['Of December']);

    await tester.tap(find.byTooltip('Go to today'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('No releases on this day.'), findsOneWidget);
    semantics.dispose();
    await calendar.stop(tester);
  });

  // Screen reader and keyboard focus stay on a control only while its element
  // does.
  for (final (view, button, shows) in [
    (CalendarTab.month, 'Previous month', 'October 2026'),
    (CalendarTab.month, 'Next month', 'December 2026'),
    (CalendarTab.downloaded, 'Previous day', 'Wednesday, November 25, 2026'),
  ]) {
    testWidgets('$button keeps the focus on its button', (tester) async {
      final calendar = await CalendarHarness.start(tester, now: noon);
      await calendar.pump(tester, tab: view);
      final icon = find.descendant(
        of: find.byTooltip(button),
        matching: find.byType(Icon),
      );
      final element = tester.element(icon);
      final focus = Focus.of(element)..requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      // Also while the new days are being read.
      await tester.pump();
      expect(find.text(shows), findsOneWidget);
      expect(tester.element(icon), same(element));
      expect(focus.hasPrimaryFocus, isTrue);

      await tester.pumpAndSettle();
      expect(tester.element(icon), same(element));
      expect(focus.hasPrimaryFocus, isTrue);
      await calendar.stop(tester);
    });
  }

  // The indicator of a pull outlasts the read it started when the view moves
  // on, or when the services change.
  for (final (view, move) in [
    (CalendarTab.downloaded, 'Previous day'),
    (CalendarTab.month, 'Next month'),
    (CalendarTab.agenda, null),
  ]) {
    testWidgets('a pull held up ends with ${move ?? 'a change of services'}, '
        'and the next one reads', (tester) async {
      final calendar = await CalendarHarness.start(tester, now: noon);
      await calendar.pump(tester, tab: view);
      final films = calendar.server('Films');
      int reads() => films.days.length + films.ranges.length;
      Future<void> pumpFor() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> pull() async {
        await tester.fling(
          find.byType(ListView).first,
          const Offset(0, 400),
          1000,
        );
        await pumpFor();
      }

      final held = Completer<void>();
      films.held = held;
      await pull();
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      films.held = null;
      if (move != null) {
        await tester.tap(find.byTooltip(move));
      } else {
        await calendar.app.services.profiles.deleteInstance(
          calendar.ids['Shows']!,
        );
        await calendar.app.services.registry.refresh();
      }
      await pumpFor();
      expect(find.byType(RefreshProgressIndicator), findsNothing);

      final before = reads();
      await pull();
      expect(reads(), before + 1);
      expect(find.byType(RefreshProgressIndicator), findsNothing);

      held.complete();
      await tester.pumpAndSettle();
      await calendar.stop(tester);
    });
  }

  testWidgets('a wide window shows the day beside the month', (tester) async {
    final calendar = await CalendarHarness.start(
      tester,
      now: noon,
      size: const Size(900, 700),
    );
    calendar.release('Films', 'Film', DateTime(2026, 11, 26));

    await calendar.pump(tester, tab: CalendarTab.month);

    expect(tester.getTopLeft(find.text('Film')).dx, greaterThan(450));
    await calendar.stop(tester);
  });

  testWidgets('an item without a screen opens the page that says so', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.release('Films', 'Film', DateTime(2026, 11, 26));
    await calendar.pump(tester);

    await tester.tap(find.text('Film'));
    await tester.pumpAndSettle();

    expect(find.text('placeholder of Film'), findsOneWidget);
    await calendar.stop(tester);
  });

  testWidgets('an item opens the screen its module names', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.release('Films', 'Film', DateTime(2026, 11, 26), id: 42);
    calendar.server('Films').hasDetails = true;
    await calendar.pump(tester);

    await tester.tap(find.text('Film'));
    await tester.pumpAndSettle();

    expect(find.text('details of 42'), findsOneWidget);
    await calendar.stop(tester);
  });

  for (final view in CalendarTab.values) {
    testWidgets('the ${view.name} view holds large text on a narrow phone', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final calendar = await CalendarHarness.start(
        tester,
        now: noon,
        size: const Size(360, 640),
      );
      calendar
        ..release(
          'Shows',
          'A series with a long name - S01E01 - And a long episode title',
          DateTime(2026, 11, 26, 20).toUtc(),
          kind: CalendarDateKind.airDate,
        )
        ..imported('Shows', 'An imported film', DateTime(2026, 11, 26, 9));
      calendar.server('Films').failure = const Unreachable();

      await calendar.pump(tester, tab: view, textScale: 2);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await calendar.stop(tester);
    });
  }
}
