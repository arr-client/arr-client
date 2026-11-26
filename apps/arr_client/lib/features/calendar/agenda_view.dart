import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'calendar_data.dart';
import 'calendar_page.dart';
import 'calendar_tiles.dart';
import 'merge.dart';
import 'today.dart';

/// What is coming up, day by day from today. Today is always listed, and later
/// days only when they have releases.
class AgendaView extends StatelessWidget {
  const AgendaView({
    required this.today,
    required this.days,
    required this.onMore,
    required this.hidden,
    required this.onHiddenChanged,
    super.key,
  });

  final DateTime today;

  /// How many days, today included, are listed.
  final int days;

  /// Asks for later days.
  final VoidCallback onMore;

  final Set<String> hidden;
  final ValueChanged<Set<String>> onHiddenChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return CalendarPage<CalendarEvent>(
      provider: agendaEventsProvider(today),
      hidden: hidden,
      onHiddenChanged: onHiddenChanged,
      builder: (content) {
        final byDay = releasesByDay(content.answers);
        final tomorrow = addDays(today, 1);
        String heading(DateTime day) {
          final date = formatDay(context, day);
          if (day == today) return strings.calendarTodayDate(date);
          if (day == tomorrow) return strings.calendarTomorrowDate(date);
          return date;
        }

        final listed = {
          today,
          ...byDay.keys.where((day) => !day.isBefore(today)),
        };
        return [
          for (final day in listed) ...[
            DayHeading(heading(day)),
            if (byDay[day] case final releases?)
              for (final release in releases)
                ReleaseTile(release: release, showService: content.several)
            else
              CalendarNote(
                content.isComplete
                    ? strings.calendarNothingToday
                    : strings.calendarNothingKnown,
              ),
          ],
          // Not while later days are still being read.
          if (content.isComplete && !content.isReading && listed.length == 1)
            CalendarNote(strings.calendarNothingLater(days - 1)),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: OutlinedButton(
                onPressed: onMore,
                child: Text(strings.calendarShowLater),
              ),
            ),
          ),
        ];
      },
    );
  }
}
