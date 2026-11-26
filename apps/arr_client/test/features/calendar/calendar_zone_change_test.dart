/// A change of the device's time zone while the calendar is open: a chosen day
/// stays the same date. In a file of its own, as it changes the zone of the
/// whole process.
@TestOn('linux || mac-os')
library;

import 'package:arr_client/features/calendar/calendar_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_downloads_test.dart' show resume;
import 'calendar_screen_test.dart' show titles;
import 'device_zone.dart';
import 'support.dart';

// West to east and back, far enough that a local midnight of one is another day
// or another time of day in the other.
const _moves = [
  ('America/New_York', 'Pacific/Auckland'),
  ('Pacific/Auckland', 'America/New_York'),
];

void main() {
  tearDown(() => setDeviceZone(startZone));

  test('the zone of the process can be changed', () {
    setDeviceZone('Asia/Kolkata');
    expect(
      DateTime(2026, 11, 26).timeZoneOffset,
      const Duration(hours: 5, minutes: 30),
    );
  });

  for (final (from, to) in _moves) {
    testWidgets('a day chosen in the month stays from $from to $to', (
      tester,
    ) async {
      setDeviceZone(from);
      final calendar = await CalendarHarness.start(
        tester,
        now: DateTime(2026, 11, 26, 12),
      );
      calendar.release('Films', 'Film', DateTime(2026, 11, 30));
      await calendar.pump(tester, tab: CalendarTab.month);
      await tester.tap(find.text('30'));
      await tester.pumpAndSettle();
      expect(titles(tester), ['Film']);

      // As an instant, noon is on another day after the move in neither
      // direction that matters here: the date is set anew.
      setDeviceZone(to);
      calendar.now = DateTime(2026, 11, 26, 12);
      // The server's adapter makes its dates in the zone of the read.
      calendar.server('Films').releases.clear();
      calendar.release('Films', 'Film', DateTime(2026, 11, 30));
      await resume(tester);

      expect(find.text('Monday, November 30, 2026'), findsOneWidget);
      expect(titles(tester), ['Film']);
      await calendar.stop(tester);
    });

    testWidgets('yesterday stays chosen from $from to $to', (tester) async {
      setDeviceZone(from);
      final calendar = await CalendarHarness.start(
        tester,
        now: DateTime(2026, 11, 26, 12),
      );
      calendar.imported('Films', 'Of yesterday', DateTime(2026, 11, 25, 12));
      await calendar.pump(tester, tab: CalendarTab.downloaded);
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(titles(tester), ['Of yesterday']);

      setDeviceZone(to);
      calendar.now = DateTime(2026, 11, 26, 12);
      calendar.server('Films').imports.clear();
      calendar.imported('Films', 'Of yesterday', DateTime(2026, 11, 25, 12));
      await resume(tester);

      expect(find.text('Downloaded yesterday'), findsOneWidget);
      expect(find.text('Wednesday, November 25, 2026'), findsOneWidget);
      expect(titles(tester), ['Of yesterday']);
      expect(calendar.server('Films').days.last, DateTime(2026, 11, 25));
      await calendar.stop(tester);
    });
  }
}
