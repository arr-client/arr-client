/// What is coming up, was downloaded today and was added lately, on Home (spec
/// story 6). CI runs this in zones east and west of UTC as well.
library;

import 'dart:async';

import 'package:arr_client/features/calendar/today.dart';
import 'package:arr_client/features/home/home_freshness.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../activity/queue/support.dart' show entry, go, step;
import 'support.dart';

final noon = DateTime(2026, 11, 26, 12);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await step(tester);
}

/// Leaves Home for another destination and comes back.
Future<void> _leaveAndReturn(WidgetTester tester) async {
  await go(tester, 'More');
  await go(tester, 'Home');
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
      ..release('Films', 'Sixth', DateTime(2026, 12, 4))
      ..release('Films', 'Beyond the limit', DateTime(2026, 12, 5))
      ..release('Films', 'Too far off', DateTime(2027, 2));

    await home.pump(tester);

    expect(rowsOf(tester, 'Coming up'), [
      'Film of today',
      'Episode tomorrow',
      'Third',
      'Fourth',
      'Fifth',
      'Sixth',
    ]);
    expect(find.text('1 more not shown'), findsOneWidget);
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

  for (final link in ['Downloads by day', 'More']) {
    testWidgets('the downloads of the calendar are read when opened: $link', (
      tester,
    ) async {
      final home = await HomeHarness.start(tester, now: noon);
      home.imported('Films', 'Early film', DateTime(2026, 11, 26, 8));
      await home.pump(tester);
      home.imported('Films', 'Late film', DateTime(2026, 11, 26, 11), id: 2);
      final gate = Completer<void>();
      home.server('Films').held = gate;

      if (link == 'More') {
        await go(tester, 'More');
        await _tap(tester, find.text('Calendar'));
        await _tap(tester, find.text('Downloaded'));
      } else {
        await _tap(tester, find.text(link));
      }

      // What Home had is there while it is read again.
      expect(find.text('Early film'), findsOneWidget);
      expect(find.text('Late film'), findsNothing);
      gate.complete();
      await step(tester);
      expect(find.text('Late film'), findsOneWidget);
      await home.stop(tester);
    });
  }

  testWidgets('the downloads are read again when their view is come back to', (
    tester,
  ) async {
    final home = await HomeHarness.start(tester, now: noon);
    await home.pump(tester);
    await go(tester, 'More');
    await _tap(tester, find.text('Calendar'));
    await _tap(tester, find.text('Downloaded'));
    await go(tester, 'Activity');
    home.imported('Films', 'New film', DateTime(2026, 11, 26, 11));

    await go(tester, 'More');

    expect(find.text('New film'), findsOneWidget);
    await home.stop(tester);
  });

  testWidgets('reads again when come back to, but not over and over', (
    tester,
  ) async {
    final home = await HomeHarness.start(tester, now: noon);
    await home.pump(tester);
    final films = home.server('Films');
    home.imported('Films', 'New film', DateTime(2026, 11, 26, 11));

    await _leaveAndReturn(tester);
    expect(films.importReads, 1, reason: 'too soon');

    home.now = home.now.add(homeReturnInterval);
    await _leaveAndReturn(tester);
    expect(films.importReads, 2);
    expect(rowsOf(tester, 'Downloaded today'), ['New film']);
    expect(rowsOf(tester, 'Recently added'), ['New film']);

    await _leaveAndReturn(tester);
    expect(films.importReads, 2);

    // Back from a page above it, too.
    await _tap(tester, find.text('Open calendar'));
    home.now = home.now.add(homeReturnInterval);
    await _tap(tester, find.byType(BackButton));
    expect(films.importReads, 3);
    await home.stop(tester);
  });

  testWidgets('reads the imports when an entry leaves a queue', (tester) async {
    const poll = Duration(seconds: 4);
    final home = await HomeHarness.start(tester, now: noon);
    final films = home.server('Films');
    films.queue.items = [entry(1, 'A film'), entry(2, 'Another')];
    await home.pump(tester);
    expect(films.importReads, 1);

    await tester.pump(poll);
    await step(tester);
    expect(films.importReads, 1, reason: 'nothing left the queue');

    // A queue that cannot be read says nothing of what left it.
    films.queue.failure = const Unreachable();
    await tester.pump(poll);
    await step(tester);
    expect(films.importReads, 1);

    films.queue
      ..failure = null
      ..items = [entry(2, 'Another')];
    home.imported('Films', 'A film', DateTime(2026, 11, 26, 12));
    await tester.pump(poll * 2);
    await step(tester);

    expect(films.importReads, 2);
    expect(home.server('Shows').importReads, 1);
    expect(rowsOf(tester, 'Downloaded today'), ['A film']);
    await home.stop(tester);
  });

  testWidgets('reads imports once at a time, however much leaves the queue', (
    tester,
  ) async {
    const poll = Duration(seconds: 4);
    final home = await HomeHarness.start(tester, now: noon);
    final films = home.server('Films');
    films.queue.items = [for (var i = 1; i <= 3; i++) entry(i, 'Film $i')];
    await home.pump(tester);
    final gate = Completer<void>();
    films.held = gate;

    for (var left = 2; left >= 0; left--) {
      films.queue.items = [for (var i = 1; i <= left; i++) entry(i, 'Film $i')];
      await tester.pump(poll);
      await step(tester);
    }
    expect(films.importReads, 2, reason: 'one under way');

    gate.complete();
    await step(tester);
    expect(films.importReads, 3, reason: 'once more for what left meanwhile');
    await home.stop(tester);
  });

  testWidgets('each service keeps its rows, however many another has', (
    tester,
  ) async {
    final home = await HomeHarness.start(tester, now: noon);
    for (var i = 1; i <= 8; i++) {
      home
        ..release('Shows', 'Episode $i', DateTime(2026, 11, 27, i))
        ..imported('Shows', 'Import $i', DateTime(2026, 11, 26, i), id: i);
    }
    home
      ..release('Films', 'A later film', DateTime(2026, 12, 15))
      ..imported('Films', 'An early film', DateTime(2026, 11, 26, 0, 30));

    await home.pump(tester);

    expect(rowsOf(tester, 'Coming up'), [
      for (var i = 1; i <= 5; i++) 'Episode $i',
      'A later film',
    ]);
    final newest = [for (var i = 8; i >= 4; i--) 'Import $i', 'An early film'];
    expect(rowsOf(tester, 'Downloaded today'), newest);
    expect(rowsOf(tester, 'Recently added'), newest);
    // Of what is coming up and of today; how much there is of what was added
    // lately is not known.
    expect(find.text('3 more not shown'), findsNWidgets(2));
    expect(find.text('See all 9 downloads from today'), findsOneWidget);
    await home.stop(tester);
  });
}
