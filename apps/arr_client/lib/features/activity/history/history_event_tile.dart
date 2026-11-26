import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'server_text.dart';

/// Which episode of its series [episode] is.
String historyEpisodeLabel(AppLocalizations strings, Episode episode) =>
    episode.seasonNumber == 0
    ? strings.historySpecialCode(episode.episodeNumber)
    : strings.historyEpisodeCode(episode.seasonNumber, episode.episodeNumber);

/// One event of a history: what happened, to which release, when, and what the
/// server says about it. A grab that is [markable] can be marked as failed.
class HistoryEventTile extends StatelessWidget {
  const HistoryEventTile(
    this.event, {
    this.episode,
    this.instanceName,
    this.markable = false,
    this.onMarkFailed,
    super.key,
  });

  final HistoryEvent event;

  /// The episode the event is about, in the history of a whole series.
  final Episode? episode;

  /// Set where several instances are shown.
  final String? instanceName;

  final bool markable;

  /// Null while the event cannot be marked.
  final VoidCallback? onMarkFailed;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final (label, icon) = switch (event.eventType) {
      HistoryEventType.grabbed => (
        strings.historyGrabbed,
        Icons.download_outlined,
      ),
      HistoryEventType.imported => (
        strings.historyImported,
        Icons.download_done,
      ),
      HistoryEventType.failed => (strings.historyFailed, Icons.error_outline),
      HistoryEventType.renamed => (
        strings.historyRenamed,
        Icons.drive_file_rename_outline,
      ),
      HistoryEventType.deleted => (
        strings.historyDeleted,
        Icons.delete_outline,
      ),
      HistoryEventType.other => (strings.historyOther, Icons.history),
    };
    // Only the values the user has a name for; the rest are the server's
    // internals.
    String? detail(String key) => serverText(event.details[key]);
    final details = [
      if (detail('message') case final value?) strings.historyMessage(value),
      if (detail('reason') case final value?) strings.historyReason(value),
      if (detail('indexer') case final value?) strings.historyIndexer(value),
      if (detail('downloadClientName') ?? detail('downloadClient')
          case final value?)
        strings.historyDownloadClient(value),
      if (detail('releaseGroup') case final value?)
        strings.historyReleaseGroup(value),
    ];

    final tile = MergeSemantics(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        titleAlignment: ListTileTitleAlignment.top,
        leading: Icon(icon),
        title: Text(label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (episode case final episode?)
              Text(historyEpisodeLabel(strings, episode)),
            if (serverText(event.sourceTitle) case final title?) Text(title),
            Text(
              strings.historyDateAndTime(
                formatDay(context, event.date),
                formatTime(context, event.date),
              ),
            ),
            for (final line in details) Text(line),
            if (instanceName case final name?) Text(name),
          ],
        ),
      ),
    );
    if (!markable || event.eventType != HistoryEventType.grabbed) return tile;

    // What a screen reader says of the button, which is not read as a part of
    // the event.
    final target = [
      serverText(event.sourceTitle) ?? strings.historyUntitled,
      if (episode case final episode?) historyEpisodeLabel(strings, episode),
      ?instanceName,
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: onMarkFailed,
            child: Text(
              strings.historyMarkFailed,
              semanticsLabel: strings.historyMarkFailedOf(target),
            ),
          ),
        ),
      ],
    );
  }
}
