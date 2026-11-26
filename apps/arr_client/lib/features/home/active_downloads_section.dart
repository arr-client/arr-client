import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation/destinations.dart';
import '../../app/navigation/locations.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../activity/queue/queue_controller.dart';
import '../activity/queue/queue_entry_summary.dart';
import '../activity/queue/queue_instance_notice.dart';
import '../activity/queue/queue_labels.dart';
import '../activity/queue/queue_watch.dart';
import 'home_section.dart';

/// The download queues, read while Home is on screen. Entries with errors and
/// warnings come first, so that the limit on rows does not hide them.
class ActiveDownloadsSection extends StatelessWidget {
  const ActiveDownloadsSection({super.key});

  @override
  Widget build(BuildContext context) => const QueueWatch(child: _Downloads());
}

class _Downloads extends ConsumerWidget {
  const _Downloads();

  static int _rank(QueueItem item) => switch (item.severity) {
    QueueSeverity.error => 0,
    QueueSeverity.warning => 1,
    QueueSeverity.ok || QueueSeverity.unknown => 2,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final queues = ref.watch(queueProvider).queues;
    if (queues.isEmpty) return const SliverToBoxAdapter();
    final all = [
      for (final queue in queues)
        for (final item in queue.items ?? const <QueueItem>[]) (queue, item),
    ];
    // `List.sort` is not stable, so the position breaks ties.
    final ranked = all.indexed.toList()
      ..sort((a, b) {
        final order = _rank(a.$2.$2).compareTo(_rank(b.$2.$2));
        return order != 0 ? order : a.$1.compareTo(b.$1);
      });

    return HomeSection(
      title: strings.homeActiveDownloads,
      children: [
        for (final queue in queues)
          if (queue.items == null || queue.isStale)
            QueueInstanceNotice(
              key: ValueKey(queue.instance.instance.id),
              queue: queue,
              onRetry: () => unawaited(
                ref
                    .read(queueProvider.notifier)
                    .retry(queue.instance.instance.id),
              ),
            ),
        for (final (_, (queue, item)) in ranked.take(homeRowLimit))
          ListTile(
            key: ValueKey((queue.instance.instance.id, item.id)),
            title: Text(
              queueTitle(strings, item),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: QueueEntrySummary(
              item: item,
              instanceName: queues.length > 1
                  ? queue.instance.instance.name
                  : null,
            ),
            onTap: () => unawaited(
              context.push<void>(
                queueEntryLocation(queue.instance.instance.id, item.id),
              ),
            ),
          ),
        if (all.isEmpty && queues.any((queue) => queue.items != null))
          HomeNote(
            queues.every((queue) => queue.items != null && !queue.isStale)
                ? strings.queueEmpty
                : strings.homeNoQueueKnown,
          ),
        HomeSectionLink(
          label: all.length > homeRowLimit
              ? strings.homeAllQueue(all.length)
              : strings.homeOpenQueue,
          onPressed: () =>
              context.go(destinationLocation(AppDestination.activity)),
        ),
      ],
    );
  }
}
