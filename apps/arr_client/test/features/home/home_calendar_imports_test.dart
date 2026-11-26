/// What is coming up, was downloaded today and was added lately, on Home (spec
/// story 6). CI runs this in zones east and west of UTC as well.
library;

import 'dart:async';

import 'package:arr_client/features/calendar/today.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../activity/queue/support.dart' show step;
import 'support.dart';

final noon = DateTime(2026, 11, 26, 12);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await step(tester);
}

Future<void> _resume(WidgetTester tester) async {
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await step(tester);
}

void main() {
  testWidgets('lists what is coming up from every service, by day', (
    tester,
  ) async {
    final home = await HomeHarness.start(tester, now: noon);
    home
      ..release('Films', 'Past film', DateTime(2026, 11, 25))
      ..release('Films', 'Film of today', DateTime(2026, 11, 26))
      ..release('Shows', 'Episode tomorrow', DateTime(2026, 11, 27, 20))
      ..release('Films', 'Third', DateTime(2026, 12, 1))
      ..release('Films', 'Fourth', DateTime(2026, 12, 2))
      ..release('Films', 'Fifth', DateTime(2026, 12, 3))
      ..release('Films', 'Beyond the limit', DateTime(2026, 12, 4))
      ..release('Films', 'Too far off', DateTime(2027, 2));

    await home.pump(tester);

    expect(rowsOf(tester, 'Coming up'), [
      'Film of today',
      'Episode tomorrow',
      'Third',
      'Fourth',
      'Fifth',
    ]);
    expect(find.text('Today, Thursday, November 26, 2026'), findsOneWidget);
    expect(find.text('Tomorrow, Friday, November 27, 2026'), findsOneWidget);
    await home.stop(tester);
  });

  testWidgets('lists what was downloaded today, newest first', (tester) async {
    final home = await HomeHarness.start(tester, now: noon);
    home
      ..imported('Films', 'Just after midnight', DateTime(2026, 11, 26, 0, 5))
      ..imported('Shows', 'Late episode', DateTime(2026, 11, 26, 11), id: 2)
      ..imported('Films', 'Of yesterday', DateTime(2026, 11, 25, 23, 55), id: 3)
      ..imported('Films', 'Of last week', DateTime(2026, 11, 19, 8), id: 4);

    await home.pump(tester);

    expect(rowsOf(tester, 'Downloaded today'), [
      'Late episode',
      'Just after midnight',
    ]);
    expect(rowsOf(tester, 'Recently added'), [
      'Late episode',
      'Just after midnight',
      'Of yesterday',
      'Of last week',
    ]);
    expect(find.text('11:00 AM · WEBDL-1080p · Shows'), findsNWidgets(2));
    expect(
      find.text('Yesterday, Wednesday, November 25, 2026'),
      findsOneWidget,
    );
    expect(find.text('Thursday, November 19, 2026'), findsOneWidget);
    await home.stop(tester);
  });

  testWidgets('opens an item, and earlier days of downloads', (tester) async {
    final home = await HomeHarness.start(tester, now: noon);
    await home.pump(tester);

    await _tap(tester, find.text('Downloads by day'));
    expect(find.widgetWithText(AppBar, 'Calendar'), findsOneWidget);
    expect(find.byTooltip('Previous day'), findsOneWidget);

    await _tap(tester, find.byType(BackButton));
    await _tap(tester, find.text('Open calendar'));
    expect(find.text('Show later days'), findsOneWidget);

    await _tap(tester, find.byType(BackButton));
    expect(find.text('Coming up'), findsOneWidget);
    await home.stop(tester);
  });

  testWidgets('says how many more were downloaded today', (tester) async {
    final home = await HomeHarness.start(tester, now: noon);
    for (var i = 1; i <= 7; i++) {
      home.imported('Films', 'Film $i', DateTime(2026, 11, 26, i), id: i);
    }

    await home.pump(tester);

    expect(rowsOf(tester, 'Downloaded today'), hasLength(5));
    expect(find.text('See all 7 downloads from today'), findsOneWidget);
    await home.stop(tester);
  });

  testWidgets('starts the day anew after midnight', (tester) async {
    final home = await HomeHarness.start(
      tester,
      now: DateTime(2026, 11, 26, 23, 59),
    );
    home
      ..imported('Films', 'Of that day', DateTime(2026, 11, 26, 23))
      ..release('Films', 'Release of that day', DateTime(2026, 11, 26));
    await home.pump(tester);
    expect(rowsOf(tester, 'Downloaded today'), ['Of that day']);

    home.now = addDays(home.now, 1);
    await _resume(tester);

    expect(rowsOf(tester, 'Downloaded today'), isEmpty);
    expect(rowsOf(tester, 'Coming up'), isEmpty);
    expect(find.text('Nothing downloaded yet today.'), findsOneWidget);
    expect(find.text('Nothing coming up in the next 30 days.'), findsOneWidget);
    expect(rowsOf(tester, 'Recently added'), ['Of that day']);
    await home.stop(tester);
  });

  testWidgets('a service that fails hides nothing, and is retried alone', (
    tester,
  ) async {
    final home = await HomeHarness.start(tester, now: noon);
    home
      ..imported('Films', 'A film', DateTime(2026, 11, 26, 9))
      ..release('Films', 'Next film', DateTime(2026, 11, 27))
      ..imported('Shows', 'An episode', DateTime(2026, 11, 26, 10));
    home.server('Shows').failure = const Unreachable();

    await home.pump(tester);

    expect(rowsOf(tester, 'Coming up'), ['Next film']);
    expect(rowsOf(tester, 'Downloaded today'), ['A film']);
    expect(rowsOf(tester, 'Recently added'), ['A film']);
    // One for each of: upcoming, today, recent, health and disk.
    final retries = find.bySemanticsLabel('Retry Shows');
    expect(find.widgetWithText(TextButton, 'Retry'), findsNWidgets(5));
    expect(find.bySemanticsLabel('Retry Films'), findsNothing);

    home.server('Shows').failure = null;
    final healthReads = home.server('Shows').healthReads;
    await _tap(tester, retries.at(1));

    expect(rowsOf(tester, 'Downloaded today'), ['An episode', 'A film']);
    // The others wait to be retried themselves.
    expect(rowsOf(tester, 'Recently added'), ['A film']);
    expect(home.server('Shows').healthReads, healthReads);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNWidgets(4));
    await home.stop(tester);
  });

  testWidgets('a slow service holds up nobody', (tester) async {
    final home = await HomeHarness.start(tester, now: noon);
    home.imported('Films', 'A film', DateTime(2026, 11, 26, 9));
    final gate = Completer<void>();
    home.server('Shows').held = gate;

    await home.pump(tester);

    expect(rowsOf(tester, 'Downloaded today'), ['A film']);
    expect(find.bySemanticsLabel('Loading from Shows'), findsWidgets);
    expect(find.text('Nothing downloaded yet today.'), findsNothing);

    gate.complete();
    await step(tester);
    expect(find.bySemanticsLabel('Loading from Shows'), findsNothing);
    await home.stop(tester);
  });

  testWidgets('the refresh button reads again', (tester) async {
    final home = await HomeHarness.start(tester, now: noon);
    await home.pump(tester);
    expect(find.text('Nothing downloaded yet today.'), findsOneWidget);
    final reads = home.server('Films').eventReads;
    home.imported('Films', 'New film', DateTime(2026, 11, 26, 11));

    await _tap(tester, find.byTooltip('Refresh'));

    expect(rowsOf(tester, 'Downloaded today'), ['New film']);
    expect(home.server('Films').eventReads, reads + 1);
    await home.stop(tester);
  });
}
