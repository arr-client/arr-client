import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'history_event_tile.dart';
import 'server_changes.dart';

/// Asks whether the grab [event] of [instance] should be marked as failed and,
/// once confirmed, says so to the server, once.
///
/// [loaded] are the events of that instance on screen. [nameInstance] is set
/// where several instances are shown. [context] must outlive the event's row,
/// as that can go at any time. Whoever shows the history reads it again after
/// the answer, whatever it was.
Future<void> markEventFailed(
  BuildContext context,
  WidgetRef ref,
  ActiveInstance instance,
  HistoryEvent event, {
  required Iterable<HistoryEvent> loaded,
  Episode? episode,
  bool nameInstance = false,
}) async {
  final strings = AppLocalizations.of(context);
  final changes = ref.read(serverChangesProvider.notifier);
  final name = instance.instance.name;
  final download = event.downloadId;
  final shared = download != null && download.isNotEmpty;
  // What is shown of the same download cannot be marked meanwhile.
  final affected = {
    event.id,
    if (shared)
      for (final other in loaded)
        if (other.eventType == HistoryEventType.grabbed &&
            other.downloadId == download)
          other.id,
  };

  final confirmed = await showConfirmDialog(
    context,
    title: strings.historyMarkFailedTitle,
    target: [
      serverText(event.sourceTitle) ?? strings.historyUntitled,
      if (episode != null) historyEpisodeLabel(strings, episode),
      if (nameInstance) name,
    ].join('\n'),
    consequence: [
      strings.historyMarkFailedConsequence,
      // The grabs of one download can be several episodes. A movie's is one.
      if (shared && event.itemRef?.kind == MediaKind.episode)
        strings.historyMarkFailedShared,
    ].join('\n\n'),
    confirmLabel: strings.historyMarkFailed,
  );
  if (!confirmed || !context.mounted) return;
  if (!instance.isCurrent) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.queueServiceChanged(name))));
    return;
  }
  await runAction<void>(
    context,
    action: () => changes.markFailed(instance, event.id, affected: affected),
    acceptedMessage: strings.historyMarkFailedAccepted(name),
    describeFailure: (message) => strings.queueFailureOn(name, message),
    // Every answer has the history read again.
    onRefresh: () {},
  );
}
