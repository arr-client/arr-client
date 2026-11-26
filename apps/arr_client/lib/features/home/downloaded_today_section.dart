import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation/locations.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../calendar/calendar_data.dart';
import '../calendar/calendar_screen.dart';
import '../calendar/calendar_tiles.dart';
import '../calendar/merge.dart';
import '../calendar/today.dart';
import 'home_section.dart';

/// What every service with a calendar imported since local midnight, newest
/// first (spec story 6, scenario 5), with the way to earlier days.
class DownloadedTodaySection extends ConsumerWidget {
  const DownloadedTodaySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final provider = importedOnProvider(ref.watch(todayProvider));
    final answers = ref.watch(provider);
    if (answers == null || answers.isEmpty) return const SliverToBoxAdapter();
    final (capped, left) = capEachService<ImportedItem>(
      answers,
      (answer) => [
        for (final entry in importsNewestFirst([answer])) entry.item,
      ],
    );
    final imports = importsNewestFirst(capped);

    return HomeSection(
      title: strings.calendarDownloadedToday,
      children: [
        ...homeServiceStates(
          context,
          answers,
          onRetry: (id) =>
              unawaited(ref.read(provider.notifier).reload(instanceId: id)),
        ),
        for (final entry in imports)
          ImportTile(entry: entry, showService: answers.length > 1),
        if (imports.isEmpty && answers.anyRead)
          HomeNote(
            answers.allRead
                ? strings.calendarNoImportsToday
                : strings.calendarNoImportsKnown,
          ),
        if (left > 0) HomeNote(strings.homeMoreNotShown(left)),
        HomeSectionLink(
          label: left > 0
              ? strings.homeAllDownloadedToday(imports.length + left)
              : strings.homeEarlierDownloads,
          onPressed: () => unawaited(
            context.push<void>(calendarLocation(CalendarTab.downloaded.name)),
          ),
        ),
      ],
    );
  }
}
