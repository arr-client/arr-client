import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/navigation/locations.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../calendar/calendar_data.dart';
import '../calendar/calendar_screen.dart';
import '../calendar/calendar_tiles.dart';
import '../calendar/merge.dart';
import '../calendar/today.dart';
import 'home_data.dart';
import 'home_section.dart';

/// The next releases of every service with a calendar, from today on.
class UpcomingSection extends ConsumerWidget {
  const UpcomingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final today = ref.watch(todayProvider);
    final provider = calendarEventsProvider(upcomingRange(today));
    final answers = ref.watch(provider);
    if (answers == null || answers.isEmpty) return const SliverToBoxAdapter();

    final tomorrow = addDays(today, 1);
    String heading(DateTime day) {
      final date = formatDay(context, day);
      if (day == today) return strings.calendarTodayDate(date);
      if (day == tomorrow) return strings.calendarTomorrowDate(date);
      return date;
    }

    final releases = [
      for (final MapEntry(key: day, value: releases) in releasesByDay(
        answers,
      ).entries)
        // A change of time zone can leave an earlier day in what was read.
        if (!day.isBefore(today))
          for (final release in releases) (day, release),
    ].take(homeRowLimit).toList();

    return HomeSection(
      title: strings.homeUpcoming,
      children: [
        ...homeServiceStates(
          context,
          answers,
          onRetry: (id) =>
              unawaited(ref.read(provider.notifier).reload(instanceId: id)),
        ),
        for (final (index, (day, release)) in releases.indexed) ...[
          if (index == 0 || releases[index - 1].$1 != day)
            HomeSubheading(heading(day)),
          ReleaseTile(release: release, showService: answers.length > 1),
        ],
        if (releases.isEmpty && answers.anyRead)
          HomeNote(
            answers.allRead
                ? strings.homeNothingUpcoming(upcomingDays)
                : strings.calendarNothingKnown,
          ),
        HomeSectionLink(
          label: strings.homeOpenCalendar,
          onPressed: () => unawaited(
            context.push<void>(calendarLocation(CalendarTab.agenda.name)),
          ),
        ),
      ],
    );
  }
}
