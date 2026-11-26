import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'calendar_data.dart';
import 'calendar_page.dart';
import 'calendar_tiles.dart';
import 'merge.dart';
import 'month_grid.dart';

/// A month with the number of releases of each day, and the releases of the
/// selected day below it, or beside it where there is room.
class MonthView extends StatelessWidget {
  const MonthView({
    required this.today,
    required this.selected,
    required this.onSelected,
    required this.hidden,
    required this.onHiddenChanged,
    super.key,
  });

  final DateTime today;

  /// The selected day; the month shown is its month.
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  final Set<String> hidden;
  final ValueChanged<Set<String>> onHiddenChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final first = DateTime(selected.year, selected.month);
    final next = DateTime(selected.year, selected.month + 1);

    // To today where the month has it, otherwise to its first day.
    void show(DateTime month) => onSelected(
      month.year == today.year && month.month == today.month ? today : month,
    );

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: material.previousMonthTooltip,
            onPressed: () => show(DateTime(selected.year, selected.month - 1)),
          ),
          Expanded(
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                material.formatMonthYear(first),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: strings.calendarGoToToday,
            onPressed: () => onSelected(today),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: material.nextMonthTooltip,
            onPressed: () => show(next),
          ),
        ],
      ),
    );

    return CalendarPage<CalendarEvent>(
      provider: calendarEventsProvider((from: first, to: next)),
      hidden: hidden,
      onHiddenChanged: onHiddenChanged,
      leading: [header],
      builder: (content) {
        final byDay = releasesByDay(content.answers);
        final grid = MonthGrid(
          month: first,
          today: today,
          selected: selected,
          counts: {
            for (final MapEntry(:key, :value) in byDay.entries)
              key: value.length,
          },
          onSelected: onSelected,
        );
        final day = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DayHeading(formatDay(context, selected)),
            if (byDay[selected] case final releases?)
              for (final release in releases)
                ReleaseTile(release: release, showService: content.several)
            else
              CalendarNote(
                content.isComplete
                    ? strings.calendarNothingOnDay
                    : strings.calendarNothingKnown,
              ),
          ],
        );
        return [
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 600
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [grid, day],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: grid),
                      Expanded(child: day),
                    ],
                  ),
          ),
        ];
      },
    );
  }
}
