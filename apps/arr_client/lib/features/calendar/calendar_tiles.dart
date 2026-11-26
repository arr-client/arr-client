/// The rows and notices the calendar's views share.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/navigation/locations.dart';
import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../library/state_appearance.dart';
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
                  event.state.icon,
                  // As large as the text beside it.
                  size: MediaQuery.textScalerOf(context).scale(16),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(event.state.label(strings))),
            ],
          ),
        ],
      ),
      onTap: () => openItem(context, ref, event.itemRef, event.title),
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
      onTap: itemRef == null
          ? null
          : () => openItem(context, ref, itemRef, item.title),
    );
  }
}

/// Opens the item's screen, which its module owns.
void openItem(BuildContext context, WidgetRef ref, ItemRef item, String title) {
  final library = ref
      .read(scopeProvider)
      ?.instance(item.instanceId)
      ?.capability(CapabilityKind.library);
  if (library == null) return;
  String location;
  // A module without detail screens yet throws; the page says so.
  try {
    location = library.detailRoute(item).location;
  } on UnimplementedError {
    location = itemPlaceholderLocation(item.instanceId, title);
  }
  unawaited(context.push<void>(location));
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
/// the others gave stays below it, as does what this one gave before.
class ServiceNotice<T> extends StatelessWidget {
  const ServiceNotice({required this.answer, required this.onRetry, super.key});

  /// One whose last read failed.
  final ServiceAnswer<T> answer;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final margin = screenMargin(MediaQuery.sizeOf(context).width);
    final failure = answer.failure;
    final fetchedAt = answer.fetchedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(margin, 8, margin, 0),
              child: Text(answer.name, style: theme.textTheme.titleSmall),
            ),
            if (answer.value != null && fetchedAt != null)
              StaleNotice(
                staleness: Staleness(fetchedAt: fetchedAt, failure: failure),
                onRetry: onRetry,
              )
            else
              Padding(
                padding: EdgeInsets.symmetric(horizontal: margin, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (failure != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(failureMessage(context, failure)),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: onRetry,
                        child: Text(
                          UiLocalizations.of(context).retry,
                          semanticsLabel: AppLocalizations.of(context)
                              .calendarRetryService(answer.name),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
