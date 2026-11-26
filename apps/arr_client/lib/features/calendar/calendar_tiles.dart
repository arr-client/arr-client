/// The rows and notices the calendar's views share.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import 'merge.dart';
import 'service_answer.dart';

/// One release: its title, when, what kind of date it is and the item's state.
class ReleaseTile extends ConsumerWidget {
  const ReleaseTile({
    required this.release,
    required this.showService,
    super.key,
  });

  final DatedRelease release;

  /// Whether to name the service, which matters only where there are several.
  final bool showService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final event = release.event;
    final details = [
      // The other dates are whole days.
      if (event.dateKind == CalendarDateKind.airDate)
        formatTime(context, event.date),
      ?_kindLabel(strings, event.dateKind),
      if (showService) release.service,
    ].join(' · ');
    return ListTile(
      leading: Icon(_mediaIcon(event.itemRef.kind)),
      title: Text(event.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty) Text(details),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  _stateIcon(event.state),
                  // As large as the text beside it.
                  size: MediaQuery.textScalerOf(context).scale(16),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(_stateLabel(strings, event.state))),
            ],
          ),
        ],
      ),
      onTap: () => openItem(context, ref, event.itemRef),
    );
  }
}

/// One import: its title, when it arrived and in what quality.
class ImportTile extends ConsumerWidget {
  const ImportTile({required this.entry, required this.showService, super.key});

  final DatedImport entry;
  final bool showService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = entry.item;
    final itemRef = item.itemRef;
    return ListTile(
      leading: Icon(
        itemRef == null
            ? Icons.insert_drive_file_outlined
            : _mediaIcon(itemRef.kind),
      ),
      title: Text(item.title),
      subtitle: Text(
        [
          formatTime(context, item.importedAt),
          ?item.quality?.name,
          if (showService) entry.service,
        ].join(' · '),
      ),
      // Without an item the server matched nothing to open.
      onTap: itemRef == null ? null : () => openItem(context, ref, itemRef),
    );
  }
}

/// Opens the item's screen, which its module owns.
void openItem(BuildContext context, WidgetRef ref, ItemRef item) {
  final library = ref
      .read(scopeProvider)
      ?.instance(item.instanceId)
      ?.capability(CapabilityKind.library);
  ModuleRoute? route;
  try {
    route = library?.detailRoute(item);
  } on UnimplementedError {
    // The modules have no detail screens yet; this goes when they do.
    route = null;
  }
  if (route != null) {
    unawaited(context.push(route.location));
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).calendarNoDetails)),
    );
}

/// A heading above the rows of a day.
class DayHeading extends StatelessWidget {
  const DayHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final margin = screenMargin(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 16, margin, 4),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}

/// A quiet line of text, such as that a day has nothing.
class CalendarNote extends StatelessWidget {
  const CalendarNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenMargin(MediaQuery.sizeOf(context).width),
        vertical: 8,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Says that one service could not be read, and offers to try it again. What
/// the others gave stays below it.
class ServiceNotice<T> extends StatelessWidget {
  const ServiceNotice({required this.answer, required this.onRetry, super.key});

  /// One whose last read failed.
  final ServiceAnswer<T> answer;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fetchedAt = answer.fetchedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenMargin(MediaQuery.sizeOf(context).width),
            vertical: 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(answer.name, style: theme.textTheme.titleSmall),
                          if (answer.failure case final failure?)
                            Text(failureMessage(context, failure)),
                          if (fetchedAt != null)
                            Text(
                              strings.calendarShowingEarlier(
                                formatTime(context, fetchedAt),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: onRetry,
                        child: Text(
                          UiLocalizations.of(context).retry,
                          semanticsLabel: strings.calendarRetryService(
                            answer.name,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _mediaIcon(MediaKind kind) => switch (kind) {
  MediaKind.movie => Icons.movie_outlined,
  MediaKind.series || MediaKind.episode => Icons.tv_outlined,
  MediaKind.artist ||
  MediaKind.album ||
  MediaKind.track => Icons.album_outlined,
  MediaKind.author || MediaKind.book => Icons.book_outlined,
};

String? _kindLabel(AppLocalizations strings, CalendarDateKind kind) =>
    switch (kind) {
      CalendarDateKind.inCinemas => strings.calendarInCinemas,
      CalendarDateKind.digitalRelease => strings.calendarDigitalRelease,
      CalendarDateKind.physicalRelease => strings.calendarPhysicalRelease,
      CalendarDateKind.airDate => strings.calendarAirs,
      CalendarDateKind.releaseDate => strings.calendarReleased,
      CalendarDateKind.unknown => null,
    };

String _stateLabel(AppLocalizations strings, ItemState state) =>
    switch (state) {
      ItemState.downloading => strings.stateDownloading,
      ItemState.downloaded => strings.stateDownloaded,
      ItemState.partial => strings.statePartial,
      ItemState.unmonitored => strings.stateUnmonitored,
      ItemState.unreleased => strings.stateUnreleased,
      ItemState.missing => strings.stateMissing,
    };

IconData _stateIcon(ItemState state) => switch (state) {
  ItemState.downloading => Icons.downloading_outlined,
  ItemState.downloaded => Icons.check_circle_outline,
  ItemState.partial => Icons.incomplete_circle_outlined,
  ItemState.unmonitored => Icons.visibility_off_outlined,
  ItemState.unreleased => Icons.schedule_outlined,
  ItemState.missing => Icons.error_outline,
};
