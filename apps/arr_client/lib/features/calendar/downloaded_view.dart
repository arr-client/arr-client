import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'calendar_data.dart';
import 'calendar_page.dart';
import 'calendar_tiles.dart';
import 'merge.dart';
import 'today.dart';

/// What was imported on one local day, newest first, with a way back to
/// earlier days.
class DownloadedView extends StatelessWidget {
  const DownloadedView({
    required this.today,
    required this.day,
    required this.onDay,
    required this.hidden,
    required this.onHiddenChanged,
    super.key,
  });

  final DateTime today;

  /// The day listed, today or earlier.
  final DateTime day;
  final ValueChanged<DateTime> onDay;

  final Set<String> hidden;
  final ValueChanged<Set<String>> onHiddenChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isToday = day == today;
    final title = isToday
        ? strings.calendarDownloadedToday
        : day == addDays(today, -1)
        ? strings.calendarDownloadedYesterday
        : strings.calendarDownloadedEarlier;

    Future<void> pick() async {
      final chosen = await showDatePicker(
        context: context,
        initialDate: day,
        firstDate: DateTime(2000),
        lastDate: today,
        currentDate: today,
      );
      if (chosen != null) onDay(dayOf(chosen));
    }

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: strings.calendarPreviousDay,
            onPressed: () => onDay(addDays(day, -1)),
          ),
          Expanded(
            child: Semantics(
              container: true,
              header: true,
              liveRegion: true,
              child: Column(
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  Text(formatDay(context, day), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_calendar_outlined),
            tooltip: strings.calendarChooseDay,
            onPressed: pick,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: strings.calendarNextDay,
            onPressed: isToday ? null : () => onDay(addDays(day, 1)),
          ),
        ],
      ),
    );

    return CalendarPage<ImportedItem>(
      provider: importedOnProvider(day),
      hidden: hidden,
      onHiddenChanged: onHiddenChanged,
      leading: [header],
      builder: (content) {
        final imports = importsNewestFirst(content.answers);
        if (imports.isEmpty) {
          return [
            CalendarNote(
              !content.isComplete
                  ? strings.calendarNoImportsKnown
                  : isToday
                  ? strings.calendarNoImportsToday
                  : strings.calendarNoImports,
            ),
          ];
        }
        return [
          for (final entry in imports)
            ImportTile(entry: entry, showService: content.several),
        ];
      },
    );
  }
}
