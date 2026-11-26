import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'server_text.dart';

/// One event of a history: what happened, to which release, when, and what the
/// server says about it.
class HistoryEventTile extends StatelessWidget {
  const HistoryEventTile(this.event, {super.key});

  final HistoryEvent event;

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

    return MergeSemantics(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        titleAlignment: ListTileTitleAlignment.top,
        leading: Icon(icon),
        title: Text(label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (serverText(event.sourceTitle) case final title?) Text(title),
            Text(
              strings.historyDateAndTime(
                formatDay(context, event.date),
                formatTime(context, event.date),
              ),
            ),
            for (final line in details) Text(line),
          ],
        ),
      ),
    );
  }
}
