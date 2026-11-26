import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'activity_feed.dart';
import 'blocklist_removal.dart';
import 'feed_list.dart';
import 'server_changes.dart';
import 'server_text.dart';

/// The blocked releases of every instance that has a blocklist, newest first,
/// each with why it was blocked, and their removal.
class BlocklistScreen extends ConsumerStatefulWidget {
  const BlocklistScreen({super.key});

  @override
  ConsumerState<BlocklistScreen> createState() => _BlocklistScreenState();
}

class _BlocklistScreenState extends ConsumerState<BlocklistScreen> {
  /// Null while not selecting.
  Set<BlocklistKey>? _selected;

  bool? _visible;

  void _select(Set<BlocklistKey>? selected) =>
      setState(() => _selected = selected);

  void _toggle(BlocklistKey key) {
    final selected = {...?_selected};
    if (!selected.remove(key)) selected.add(key);
    _select(selected);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // As on the History tab: read again on the way back to it.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && _visible == false) {
      scheduleMicrotask(() {
        if (mounted) {
          unawaited(ref.read(blocklistFeedProvider.notifier).refresh());
        }
      });
    }
    _visible = visible;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final feed = ref.watch(blocklistFeedProvider);
    final changes = ref.watch(serverChangesProvider);
    final controller = ref.read(blocklistFeedProvider.notifier);
    final several = feed.sources.length > 1;

    bool canRemove(FeedRow<BlocklistEntry> row) =>
        !row.source.isStale &&
        !changes.isSending(
          row.source.instance,
          ChangeKind.unblock,
          row.item.id,
        );
    // What is no longer there is no longer selected.
    final present = {for (final row in feed.rows) _key(row)};
    final selected = feed.rows.isEmpty
        ? null
        : _selected?.intersection(present);
    final canRemoveSelected =
        selected != null &&
        selected.isNotEmpty &&
        feed.rows.every(
          (row) => !selected.contains(_key(row)) || canRemove(row),
        );

    // This state's context, which stays when the rows go.
    void remove(Set<BlocklistKey> keys) => unawaited(
      removeBlocklistEntries(context, ref, keys, onSent: () => _select(null)),
    );

    final list = FeedList<BlocklistEntry>(
      feed: feed,
      controller: controller,
      emptyMessage: strings.blocklistEmpty,
      older: (
        show: strings.blocklistShowOlder,
        failed: strings.blocklistOlderFailed,
        retry: strings.blocklistRetryOlder,
      ),
      head: [
        if (feed.rows.isNotEmpty)
          _SelectionBar(
            count: selected?.length,
            onSelect: () => _select({}),
            onCancel: () => _select(null),
            onRemove: canRemoveSelected ? () => remove(selected) : null,
          ),
      ],
      rowBuilder: (row) {
        final key = _key(row);
        return _EntryTile(
          key: ValueKey(key),
          entry: row.item,
          instanceName: several ? row.source.instance.instance.name : null,
          selected: selected?.contains(key),
          onToggle: () => _toggle(key),
          onRemove: canRemove(row) ? () => remove({key}) : null,
        );
      },
    );

    // Back leaves the selection before it leaves the screen.
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.moreBlocklist),
          actions: [
            // Pulling down does this too, which a screen reader cannot.
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: strings.blocklistRefresh,
              onPressed: feed.sources.any((source) => source.refreshing)
                  ? null
                  : () => unawaited(controller.refresh()),
            ),
          ],
        ),
        body: SafeArea(child: list),
      ),
    );
  }

  static BlocklistKey _key(FeedRow<BlocklistEntry> row) =>
      (instanceId: row.source.id, id: row.item.id);
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onSelect,
    required this.onCancel,
    required this.onRemove,
  });

  /// How many are selected; null while not selecting.
  final int? count;

  final VoidCallback onSelect;
  final VoidCallback onCancel;

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

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.instanceName,
    required this.selected,
    required this.onToggle,
    required this.onRemove,
    super.key,
  });

  final BlocklistEntry entry;

  /// Set where several instances are shown.
  final String? instanceName;

  /// Null while not selecting.
  final bool? selected;

  final VoidCallback onToggle;

  /// Null while the entry cannot be removed.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final name = serverText(entry.sourceTitle) ?? strings.historyUntitled;
    final title = Text(name);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.historyDateAndTime(
            formatDay(context, entry.date),
            formatTime(context, entry.date),
          ),
        ),
        if (serverText(entry.reason) case final reason?)
          Text(strings.historyReason(reason)),
        if (serverText(entry.quality?.name) case final quality?) Text(quality),
        if (instanceName case final instance?) Text(instance),
      ],
    );

    if (selected case final selected?) {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: selected,
        onChanged: (_) => onToggle(),
        title: title,
        subtitle: details,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            titleAlignment: ListTileTitleAlignment.top,
            leading: const Icon(Icons.block_outlined),
            title: title,
            subtitle: details,
            onLongPress: onToggle,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: onRemove,
            child: Text(
              strings.blocklistRemoveConfirm(1),
              semanticsLabel: strings.blocklistRemoveOf(name),
            ),
          ),
        ),
      ],
    );
  }
}
