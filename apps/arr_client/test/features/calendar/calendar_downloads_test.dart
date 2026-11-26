/// What was downloaded today and on earlier days (spec story 6, scenario 5),
/// and how the calendar follows the device's day. CI runs this in zones east and
/// west of UTC as well, where days on which the clocks change are among these.
library;

import 'package:arr_client/features/calendar/calendar_screen.dart';
import 'package:arr_client/features/calendar/today.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'calendar_screen_test.dart' show tab, titles;
import 'support.dart';

final noon = DateTime(2026, 11, 26, 12);

Future<void> resume(WidgetTester tester) async {
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

void main() {
  test('days are stepped by the calendar, also when the clocks change', () {
    var day = DateTime(2026);
    // A whole year, which holds both changes of any zone that has them.
    for (var i = 1; i <= 365; i++) {
      final next = addDays(day, 1);
      final noonAfter = DateTime(2026, 1, 1 + i, 12);
      expect(next, dayOf(noonAfter), reason: 'after $day');
      expect(addDays(next, -1), day, reason: 'before $next');
      day = next;
    }
    expect(day, DateTime(2027));
  });

  test('an instant belongs to the local day it falls on', () {
    for (final time in [
      DateTime(2026, 11, 26),
      DateTime(2026, 11, 26, 23, 59),
    ]) {
      expect(dayOf(time.toUtc()), DateTime(2026, 11, 26));
    }
  });

  testWidgets('today lists the imports of all services, newest first', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar
      ..imported('Films', 'Early film', DateTime(2026, 11, 26, 0, 5))
      ..imported('Shows', 'Episode', DateTime(2026, 11, 26, 9, 15))
      ..imported('Films', 'Late film', DateTime(2026, 11, 26, 11, 45), id: 2)
      ..imported('Films', 'Of yesterday', DateTime(2026, 11, 25, 23), id: 3);

    await calendar.pump(tester, tab: CalendarTab.downloaded);

    expect(find.text('Downloaded today'), findsOneWidget);
    expect(find.text('Thursday, November 26, 2026'), findsOneWidget);
    expect(titles(tester), ['Late film', 'Episode', 'Early film']);
    expect(find.text('9:15 AM · WEBDL-1080p · Shows'), findsOneWidget);
    expect(find.text('12:05 AM · WEBDL-1080p · Films'), findsOneWidget);
    await calendar.stop(tester);
  });

  testWidgets('earlier days are stepped to, and the next only up to today', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.imported('Films', 'Of yesterday', DateTime(2026, 11, 25, 8));
    await calendar.pump(tester, tab: CalendarTab.downloaded);
    IconButton next() =>
        tester.widget(find.widgetWithIcon(IconButton, Icons.chevron_right));

    expect(find.text('Nothing downloaded yet today.'), findsOneWidget);
    expect(next().onPressed, isNull);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded yesterday'), findsOneWidget);
    expect(titles(tester), ['Of yesterday']);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded'), findsWidgets);
    expect(find.text('Tuesday, November 24, 2026'), findsOneWidget);
    expect(find.text('Nothing was downloaded on this day.'), findsOneWidget);

    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded today'), findsOneWidget);
    expect(next().onPressed, isNull);
    await calendar.stop(tester);
  });

  testWidgets('a day can be chosen', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.imported('Films', 'Of the third', DateTime(2026, 11, 3, 8));
    await calendar.pump(tester, tab: CalendarTab.downloaded);

    await tester.tap(find.byTooltip('Choose a day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Tuesday, November 3, 2026'), findsOneWidget);
    expect(titles(tester), ['Of the third']);
    await calendar.stop(tester);
  });

  testWidgets('at midnight today becomes the new day', (tester) async {
    final calendar = await CalendarHarness.start(
      tester,
      now: DateTime(2026, 11, 26, 23, 59),
    );
    calendar.imported('Films', 'Before midnight', DateTime(2026, 11, 26, 20));
    await calendar.pump(tester, tab: CalendarTab.downloaded);
    expect(titles(tester), ['Before midnight']);

    calendar.now = DateTime(2026, 11, 27);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(find.text('Friday, November 27, 2026'), findsOneWidget);
    expect(find.text('Downloaded today'), findsOneWidget);
    expect(titles(tester), isEmpty);
    expect(calendar.server('Films').days.last, DateTime(2026, 11, 27));

    await tab(tester, 'Agenda');
    expect(find.text('Today, Friday, November 27, 2026'), findsOneWidget);
    await calendar.stop(tester);
  });

  // The days on which New York and Auckland change their clocks in 2026.
  for (final date in [
    DateTime(2026, 3, 8),
    DateTime(2026, 4, 5),
    DateTime(2026, 9, 27),
    DateTime(2026, 11, 1),
  ]) {
    testWidgets(
      'today ends at the next midnight after ${date.month}/${date.day}',
      (tester) async {
        final calendar = await CalendarHarness.start(tester, now: date);
        await calendar.pump(tester, tab: CalendarTab.downloaded);
        // 23, 24 or 25 hours, as the zone has it.
        final next = DateTime(date.year, date.month, date.day + 1);
        final length = next.difference(date);

        calendar.now = next.subtract(const Duration(minutes: 1));
        await tester.pump(length - const Duration(minutes: 1));
        expect(calendar.server('Films').days, [date]);

        calendar.now = next;
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(calendar.server('Films').days.last, next);
        expect(find.text('Downloaded today'), findsOneWidget);
        await calendar.stop(tester);
      },
    );
  }

  testWidgets('a clock set forward while open is noticed', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    await calendar.pump(tester, tab: CalendarTab.downloaded);

    calendar.now = DateTime(2026, 11, 30, 8);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(find.text('Monday, November 30, 2026'), findsOneWidget);
    await calendar.stop(tester);
  });

  testWidgets('resuming on a later day moves to it', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    await calendar.pump(tester, tab: CalendarTab.downloaded);

    // The app was suspended: no timer ran.
    calendar.now = DateTime(2026, 11, 29, 7);
    calendar.imported('Shows', 'This morning', DateTime(2026, 11, 29, 6));
    await resume(tester);

    expect(find.text('Sunday, November 29, 2026'), findsOneWidget);
    expect(titles(tester), ['This morning']);
    await calendar.stop(tester);
  });

  testWidgets('resuming on the same day reads again', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    await calendar.pump(tester, tab: CalendarTab.downloaded);
    expect(titles(tester), isEmpty);

    calendar.imported('Shows', 'Just arrived', DateTime(2026, 11, 26, 11, 59));
    await resume(tester);

    expect(titles(tester), ['Just arrived']);
    await calendar.stop(tester);
  });

  testWidgets('a chosen day stays when the day changes', (tester) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    await calendar.pump(tester, tab: CalendarTab.downloaded);
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();

    calendar.now = DateTime(2026, 11, 27, 12);
    await resume(tester);

    expect(find.text('Wednesday, November 25, 2026'), findsOneWidget);
    await calendar.stop(tester);
  });

  testWidgets('one failing service does not hide what others imported', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.imported('Shows', 'Episode', DateTime(2026, 11, 26, 9));
    calendar.server('Films').failure = const AuthFailed();

    await calendar.pump(tester, tab: CalendarTab.downloaded);

    expect(titles(tester), ['Episode']);
    expect(find.text('Retry'), findsOneWidget);
    await calendar.stop(tester);
  });

  testWidgets('an import the server matched to nothing cannot be opened', (
    tester,
  ) async {
    final calendar = await CalendarHarness.start(tester, now: noon);
    calendar.imported(
      'Films',
      'Some.Release.Name',
      DateTime(2026, 11, 26, 9),
      id: null,
    );

    await calendar.pump(tester, tab: CalendarTab.downloaded);

    expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    await calendar.stop(tester);
  });
}
