import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/navigation/locations.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import '../../search/add/open_item.dart';
import 'client_progress_controller.dart';
import 'client_progress_lines.dart';
import 'client_progress_notice.dart';
import 'client_progress_watch.dart';
import 'queue_actions.dart';
import 'queue_controller.dart';
import 'queue_labels.dart';
import 'queue_watch.dart';

/// One entry of an instance's queue, with the server's reasons in full.
class QueueDetailsScreen extends StatelessWidget {
  const QueueDetailsScreen({
    required this.instanceId,
    required this.queueId,
    super.key,
  });

  final String instanceId;

  /// Null if the route did not name a number, so no entry matches.
  final int? queueId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).queueEntryTitle)),
    body: SafeArea(
      child: QueueWatch(
        child: ClientProgressWatch(
          child: _Details(instanceId: instanceId, queueId: queueId),
        ),
      ),
    ),
  );
}

class _Details extends ConsumerStatefulWidget {
  const _Details({required this.instanceId, required this.queueId});

  final String instanceId;
  final int? queueId;

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final queue = ref.watch(queueProvider).queue(widget.instanceId);
    if (queue == null) {
      return StateMessage(
        icon: Icons.info_outline,
        message: strings.notOffered,
      );
    }
    final items = queue.items;
    final fetchedAt = queue.fetchedAt;
    final ViewState<List<QueueItem>> view;
    if (items != null && fetchedAt != null) {
      view = ViewData(
        items,
        staleness: queue.isStale
            ? Staleness(fetchedAt: fetchedAt, failure: queue.failure)
            : null,
      );
    } else if (queue.failure case final failure?) {
      view = ViewError(failure);
    } else {
      view = const ViewLoading();
    }
    return StateScaffold<List<QueueItem>>(
      state: view,
      onRetry: () =>
          unawaited(ref.read(queueProvider.notifier).retry(widget.instanceId)),
      builder: (_, _, {required isStale}) {
        final id = widget.queueId;
        final item = id == null ? null : queue.item(id);
        if (item == null) {
          return StateMessage(
            icon: Icons.inbox_outlined,
            message: strings.queueEntryGone,
            announce: true,
          );
        }
        final enabled = queue.canChange(item.id);
        // This state's context, which stays when the entry goes.
        return _Entry(
          queue: queue,
          item: item,
          onRemove: enabled
              ? () => unawaited(
                  removeQueueEntries(context, ref, {
                    (instanceId: widget.instanceId, id: item.id),
                  }),
                )
              : null,
          onGrab: enabled
              ? () => unawaited(grabQueueEntry(context, ref, queue, item))
              : null,
        );
      },
    );
  }
}

class _Entry extends ConsumerWidget {
  const _Entry({
    required this.queue,
    required this.item,
    required this.onRemove,
    required this.onGrab,
  });

  final InstanceQueue queue;
  final QueueItem item;
  final VoidCallback? onRemove;
  final VoidCallback? onGrab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = ref.watch(clientProgressProvider);
    final matched = progress.match(item);
    // Where it is in the library, if the server knows what it is.
    final location = switch (item.itemRef ?? item.parent) {
      final target? => itemLocation(
        queue.instance,
        target,
        queueTitle(strings, item),
      ),
      null => null,
    };
    final (icon, color) = queueSeverityIcon(theme.colorScheme, item.severity);
    final severity = queueSeverityLabel(strings, item.severity);
    final waiting = isWaitingRelease(item);
    final percent = queuePercent(context, item.progress);
    final shared = queue.goingWith(item).length - 1;

    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            Text(value),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
        children: [
          Text(queueTitle(strings, item), style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [?severity, queueStateLabel(strings, item)].join(' · '),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (item.messages.isNotEmpty) ...[
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                strings.queueReasons,
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final message in item.messages)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(message),
              ),
          ],
          if (item.needsManualImport) ...[
            const SizedBox(height: 16),
            Text(strings.queueNeedsManualImport),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: () => unawaited(
                  context.push<void>(
                    queueImportLocation(queue.instance.instance.id, item.id),
                  ),
                ),
                child: Text(strings.manualImportOpen),
              ),
            ),
          ],
          if (!waiting) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: item.progress,
              semanticsLabel: strings.queueProgress,
              semanticsValue: percent,
            ),
            const SizedBox(height: 8),
            Text(
              [
                percent,
                if (item.sizeLeft > 0)
                  strings.queueSizeLeft(formatBytes(context, item.sizeLeft)),
              ].join(' · '),
            ),
          ],
          if (queueTimeLabel(context, item) case final time?) Text(time),
          if (matched != null) ...[
            const SizedBox(height: 12),
            ClientProgressLines(
              progress: matched,
              client: progress.nameOf(matched.instanceId),
              wholeDownload: shared > 0,
            ),
          ] else if (expectsClientProgress(item))
            for (final client in progress.clients)
              if (client.failure case final failure?) ...[
                const SizedBox(height: 12),
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
          fact(strings.queueService, queue.instance.instance.name),
          if (item.quality case final quality?)
            fact(strings.queueQuality, quality.name),
          if (item.downloadClient case final client?)
            fact(strings.queueDownloadClient, client),
          if (queueProtocolLabel(strings, item.protocol) case final protocol?)
            fact(strings.queueProtocol, protocol),
          if (shared > 0) ...[
            const SizedBox(height: 16),
            Text(
              waiting
                  ? strings.queueSharedRelease(shared)
                  : strings.queueSharedDownload(shared),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.status == QueueStatus.delayed)
                FilledButton(
                  onPressed: onGrab,
                  child: Text(strings.queueGrabNow),
                ),
              if (location != null)
                OutlinedButton(
                  onPressed: () => unawaited(context.push<void>(location)),
                  child: Text(strings.queueOpenItem),
                ),
              OutlinedButton(
                onPressed: onRemove,
                child: Text(strings.queueRemoveConfirm(1)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
