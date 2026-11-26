import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// The days of a month in weeks, starting on the locale's first day. A day with
/// releases shows how many.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.counts,
    required this.onSelected,
    super.key,
  });

  /// Its first day.
  final DateTime month;
  final DateTime today;
  final DateTime selected;

  /// Releases by local day.
  final Map<DateTime, int> counts;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelMedium;
    // 0 is Sunday.
    final firstWeekday = material.firstDayOfWeekIndex;
    // The days of the first week that are of the month before.
    final lead = (month.weekday % 7 - firstWeekday + 7) % 7;
    final length = DateTime(month.year, month.month + 1, 0).day;
    final weeks = ((lead + length) / 7).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Table(
        children: [
          TableRow(
            children: [
              for (var i = 0; i < 7; i++)
                // Each day's own label says which day it is.
                ExcludeSemantics(
                  child: Text(
                    material.narrowWeekdays[(firstWeekday + i) % 7],
                    style: style,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
          for (var week = 0; week < weeks; week++)
            TableRow(
              children: [
                for (var i = 0; i < 7; i++)
                  switch (week * 7 + i - lead + 1) {
                    final number when number >= 1 && number <= length => _Day(
                      day: DateTime(month.year, month.month, number),
                      today: today,
                      selected: selected,
                      counts: counts,
                      onSelected: onSelected,
                    ),
                    _ => const SizedBox.shrink(),
                  },
              ],
            ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.today,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final DateTime day;
  final DateTime today;
  final DateTime selected;
  final Map<DateTime, int> counts;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = counts[day] ?? 0;
    final isToday = day == today;
    final isSelected = day == selected;
    // Today is outlined and the selection filled, so neither relies on a colour
    // alone.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: isToday
          ? BorderSide(color: colors.primary, width: 2)
          : BorderSide.none,
    );
    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: [
        formatDay(context, day),
        if (isToday) strings.calendarToday,
        strings.calendarReleaseCount(count),
      ].join(', '),
      onTap: () => onSelected(day),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Material(
          color: isSelected
              ? colors.primaryContainer
              : colors.surface.withValues(alpha: 0),
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: () => onSelected(day),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                // Large text shrinks rather than breaks a number in two. The
                // numbers of a week stay level, with or without a count.
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        material.formatDecimal(day.day),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? colors.onPrimaryContainer
                              : colors.onSurface,
                          fontWeight: isToday ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                    if (count > 0)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            // Also apart from the fill of the selection.
                            color: isSelected
                                ? colors.surface
                                : colors.secondaryContainer,
                            shape: const StadiumBorder(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              material.formatDecimal(count),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isSelected
                                    ? colors.onSurface
                                    : colors.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
