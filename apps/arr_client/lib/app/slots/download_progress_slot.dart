import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/activity/queue/client_progress_controller.dart';
import '../../features/activity/queue/client_progress_lines.dart';
import '../../features/activity/queue/client_progress_notice.dart';
import '../../features/activity/queue/client_progress_watch.dart';
import '../../features/activity/queue/queue_controller.dart';
import '../../features/activity/queue/queue_entry_summary.dart';
import '../../features/activity/queue/queue_instance_notice.dart';
import '../../features/activity/queue/queue_labels.dart';
import '../../features/activity/queue/visible_watch.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../navigation/locations.dart';
import '../providers.dart';

/// The queue entries of a movie, series or episode, each with the server's
/// progress and the download client's beside it (spec story 7).
///
/// Without a download client it is empty and reads nothing. Otherwise it has
/// the queue of the item's instance read while it is on screen, and the
/// download clients only while one of them could have an entry.
class DownloadProgressSlot extends ConsumerWidget {
  const DownloadProgressSlot({required this.item, super.key});

  final ItemRef item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeProvider);
    if (scope == null ||
        scope.providers(CapabilityKind.downloadProgress).isEmpty ||
        scope.instance(item.instanceId)?.capability(CapabilityKind.queue) ==
            null) {
      return const SizedBox.shrink();
    }
    return VisibleWatch(
      watch: (ref) => ref.read(queueProvider.notifier).watch(item.instanceId),
      child: _Downloads(item),
    );
  }
}

class _Downloads extends ConsumerWidget {
  const _Downloads(this.item);

  final ItemRef item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider).queue(item.instanceId);
    // A series is what the entries of its episodes belong to.
    final entries = [
      for (final entry in queue?.items ?? const <QueueItem>[])
        if (entry.itemRef == item || entry.parent == item) entry,
    ];
    // Nothing is known to be on its way.
    if (queue == null || entries.isEmpty) return const SizedBox.shrink();
    final content = _Entries(queue: queue, entries: entries);
    return entries.any(expectsClientProgress)
        ? ClientProgressWatch(child: content)
        : content;
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({required this.queue, required this.entries});

  final InstanceQueue queue;
  final List<QueueItem> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = ref.watch(clientProgressProvider);
    final instanceId = queue.instance.instance.id;

    // Entries that would read the same are shown once: a season pack has one
    // for every episode.
    final alike = <Object, List<QueueItem>>{};
    for (final entry in entries) {
      alike.putIfAbsent(_shown(entry), () => []).add(entry);
    }
    final unmatched = entries.any(
      (entry) => expectsClientProgress(entry) && progress.match(entry) == null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            strings.downloadSlotTitle,
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (queue.isStale)
          QueueInstanceNotice(
            queue: queue,
            onRetry: () =>
                unawaited(ref.read(queueProvider.notifier).retry(instanceId)),
          ),
        for (final same in alike.values)
          ListTile(
            key: ValueKey(same.first.id),
            contentPadding: EdgeInsets.zero,
            title: Text(
              queueTitle(strings, same.first),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QueueEntrySummary(
                  item: same.first,
                  clientProgress: switch (progress.match(same.first)) {
                    final matched? => ClientProgressLines(
                      progress: matched,
                      client: progress.nameOf(matched.instanceId),
                      wholeDownload: queue.goingWith(same.first).length > 1,
                    ),
                    null => null,
                  },
                ),
                if (same.length > 1)
                  Text(strings.downloadSlotEntries(same.length)),
              ],
            ),
            onTap: () => unawaited(
              context.push<void>(queueEntryLocation(instanceId, same.first.id)),
            ),
          ),
        if (unmatched)
          for (final client in progress.clients)
            if (client.failure case final failure?)
              ClientProgressNotice(
                client: progress.nameOf(client.instance.instance.id),
                failure: failure,
                onRetry: () => unawaited(
                  ref
                      .read(clientProgressProvider.notifier)
                      .retry(client.instance.instance.id),
                ),
              ),
      ],
    );
  }

  /// All that is shown of [entry].
  static Object _shown(QueueItem entry) => (
    entry.title,
    entry.downloadId?.toLowerCase(),
    entry.status,
    entry.trackedState,
    entry.severity,
    entry.messages.firstOrNull,
    entry.progress,
    entry.sizeLeft,
    entry.eta,
    entry.quality?.name,
    entry.downloadClient,
  );
}
