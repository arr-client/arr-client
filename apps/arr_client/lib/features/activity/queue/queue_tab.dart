import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/navigation/locations.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import 'queue_actions.dart';
import 'queue_controller.dart';
import 'queue_entry_summary.dart';
import 'queue_instance_notice.dart';
import 'queue_labels.dart';
import 'queue_watch.dart';

/// The Queue tab of Activity: the queues of every instance that has one.
class QueueTab extends StatelessWidget {
  const QueueTab({super.key});

  @override
  Widget build(BuildContext context) => const QueueWatch(child: _QueueList());
}

class _QueueList extends ConsumerStatefulWidget {
  const _QueueList();

  @override
  ConsumerState<_QueueList> createState() => _QueueListState();
}

class _QueueListState extends ConsumerState<_QueueList> {
  /// Null while not selecting.
  Set<QueueKey>? _selected;

  void _select(Set<QueueKey>? selected) => setState(() => _selected = selected);

  void _toggle(QueueKey key) {
    final selected = {...?_selected};
    if (!selected.remove(key)) selected.add(key);
    _select(selected);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final queues = ref.watch(queueProvider).queues;
    final controller = ref.read(queueProvider.notifier);

    // Nothing from anyone yet.
    if (queues.isNotEmpty &&
        queues.every((q) => q.items == null && q.failure == null)) {
      return Center(
        child: CircularProgressIndicator(
          semanticsLabel: UiLocalizations.of(context).loading,
        ),
      );
    }

    final rows = <(InstanceQueue, QueueItem)>[
      for (final queue in queues)
        for (final item in queue.items ?? const <QueueItem>[]) (queue, item),
    ];
    final notices = [
      for (final queue in queues)
        if (queue.items == null || queue.isStale) queue,
    ];
    // What is no longer there is no longer selected.
    final present = {for (final (queue, item) in rows) _key(queue, item)};
    final selected = rows.isEmpty ? null : _selected?.intersection(present);
    final canRemove =
        selected != null &&
        selected.isNotEmpty &&
        rows.every(
          (row) =>
              !selected.contains(_key(row.$1, row.$2)) ||
              row.$1.canChange(row.$2.id),
        );

    // The bar, the notices and the rows scroll as one, so that large text
    // leaves room for all of them.
    final head = <Widget>[
      if (rows.isNotEmpty)
        _SelectionBar(
          count: selected?.length,
          onSelect: () => _select({}),
          onCancel: () => _select(null),
          onRefresh: () => unawaited(controller.refresh()),
          onRemove: canRemove
              ? () => unawaited(
                  removeQueueEntries(
                    this.context,
                    ref,
                    selected,
                    onSent: () => _select(null),
                  ),
                )
              : null,
        ),
      for (final queue in notices)
        QueueInstanceNotice(
          key: ValueKey(queue.instance.instance.id),
          queue: queue,
          onRetry: () =>
              unawaited(controller.retry(queue.instance.instance.id)),
        ),
    ];

    final Widget list;
    if (rows.isEmpty && notices.isEmpty) {
      list = StateMessage(
        icon: Icons.inbox_outlined,
        message: strings.queueEmpty,
      );
    } else {
      list = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: head.length + rows.length,
        itemBuilder: (context, index) {
          if (index < head.length) return head[index];
          final (queue, item) = rows[index - head.length];
          final key = _key(queue, item);
          return _QueueRow(
            key: ValueKey(key),
            queue: queue,
            item: item,
            showInstance: queues.length > 1,
            selected: selected?.contains(key),
            onToggle: () => _toggle(key),
            onOpen: () => unawaited(
              context.push<void>(queueEntryLocation(key.instanceId, key.id)),
            ),
            onGrab: () =>
                unawaited(grabQueueEntry(this.context, ref, queue, item)),
          );
        },
      );
    }

    // Back leaves the selection before it leaves the screen.
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(null);
      },
      child: RefreshIndicator(onRefresh: controller.refresh, child: list),
    );
  }

  static QueueKey _key(InstanceQueue queue, QueueItem item) =>
      (instanceId: queue.instance.instance.id, id: item.id);
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onSelect,
    required this.onCancel,
    required this.onRefresh,
    required this.onRemove,
  });

  /// How many are selected; null while not selecting.
  final int? count;

  final VoidCallback onSelect;
  final VoidCallback onCancel;
  final VoidCallback onRefresh;

  /// Null while the selection cannot be removed.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final count = this.count;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: count == null
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: strings.queueRefresh,
                  onPressed: onRefresh,
                ),
                TextButton(
                  onPressed: onSelect,
                  child: Text(strings.queueSelect),
                ),
              ]
            : [
                Semantics(
                  liveRegion: true,
                  child: Text(strings.queueSelectedCount(count)),
                ),
                TextButton(
                  onPressed: onCancel,
                  child: Text(UiLocalizations.of(context).cancel),
                ),
                FilledButton.tonal(
                  onPressed: onRemove,
                  child: Text(strings.queueRemoveSelected),
                ),
              ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.queue,
    required this.item,
    required this.showInstance,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
    required this.onGrab,
    super.key,
  });

  final InstanceQueue queue;
  final QueueItem item;
  final bool showInstance;

  /// Null while not selecting.
  final bool? selected;

  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onGrab;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final title = Text(
      queueTitle(strings, item),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
    final summary = QueueEntrySummary(
      item: item,
      instanceName: showInstance ? queue.instance.instance.name : null,
    );
    if (selected case final selected?) {
      return CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: selected,
        onChanged: (_) => onToggle(),
        title: title,
        subtitle: summary,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: title,
          subtitle: summary,
          onTap: onOpen,
          onLongPress: onToggle,
        ),
        if (item.status == QueueStatus.delayed)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: queue.canChange(item.id) ? onGrab : null,
                child: Text(
                  strings.queueGrabNow,
                  semanticsLabel: strings.queueGrabNowOf(
                    queueTitle(strings, item),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
