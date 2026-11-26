import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import '../calendar/calendar_tiles.dart';
import '../calendar/merge.dart';
import '../calendar/today.dart';
import 'home_data.dart';
import 'home_section.dart';

/// The latest imports of every service with a calendar, whichever day they were
/// made, newest first under their days.
class RecentlyAddedSection extends ConsumerWidget {
  const RecentlyAddedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final today = ref.watch(todayProvider);
    final answers = ref.watch(recentlyAddedProvider);
    if (answers == null || answers.isEmpty) return const SliverToBoxAdapter();
    final imports = importsNewestFirst(answers).take(homeRowLimit).toList();
    final days = [for (final entry in imports) dayOf(entry.item.importedAt)];

    final yesterday = addDays(today, -1);
    String heading(DateTime day) {
      final date = formatDay(context, day);
      if (day == today) return strings.calendarTodayDate(date);
      if (day == yesterday) return strings.homeYesterdayDate(date);
      return date;
    }

    return HomeSection(
      title: strings.homeRecentlyAdded,
      children: [
        ...homeServiceStates(
          context,
          answers,
          onRetry: (id) => unawaited(
            ref.read(recentlyAddedProvider.notifier).reload(instanceId: id),
          ),
        ),
        for (final (index, entry) in imports.indexed) ...[
          if (index == 0 || days[index - 1] != days[index])
            HomeSubheading(heading(days[index])),
          ImportTile(entry: entry, showService: answers.length > 1),
        ],
        if (imports.isEmpty && answers.anyRead)
          HomeNote(
            answers.allRead
                ? strings.homeNothingAdded
                : strings.calendarNoImportsKnown,
          ),
      ],
    );
  }
}
