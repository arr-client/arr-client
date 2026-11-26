import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'activity_feed.dart';
import 'feed_list.dart';
import 'history_event_tile.dart';
import 'mark_failed.dart';
import 'server_changes.dart';

/// The History tab of Activity: what happened on every instance that keeps a
/// history, newest first.
class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key});

  @override
  ConsumerState<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<HistoryTab> {
  bool? _visible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A destination that is not selected keeps its screens, with their tickers
    // off. What was read before it was left is read again on the way back.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && _visible == false) {
      scheduleMicrotask(() {
        if (mounted) {
          unawaited(ref.read(historyFeedProvider.notifier).refresh());
        }
      });
    }
    _visible = visible;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final feed = ref.watch(historyFeedProvider);
    final changes = ref.watch(serverChangesProvider);
    final controller = ref.read(historyFeedProvider.notifier);
    final several = feed.sources.length > 1;

    return FeedList<HistoryEvent>(
      feed: feed,
      controller: controller,
      emptyMessage: strings.historyNone,
      older: (
        show: strings.historyShowOlder,
        failed: strings.historyOlderFailed,
        retry: strings.historyRetryOlder,
      ),
      head: [
        // Pulling down does this too, which a screen reader cannot.
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.historyRefresh,
            onPressed: feed.sources.any((source) => source.refreshing)
                ? null
                : () => unawaited(controller.refresh()),
          ),
        ),
      ],
      rowBuilder: (row) {
        final (:source, item: event) = row;
        final instance = source.instance;
        final canMark =
            !source.isStale &&
            !changes.isSending(instance, ChangeKind.markFailed, event.id);
        return HistoryEventTile(
          event,
          key: ValueKey((source.id, event.id)),
          instanceName: several ? instance.instance.name : null,
          markable: true,
          onMarkFailed: canMark
              // This state's context, which stays when the row goes.
              ? () => unawaited(
                  markEventFailed(
                    context,
                    ref,
                    instance,
                    event,
                    loaded: source.items ?? const [],
                    nameInstance: several,
                  ),
                )
              : null,
        );
      },
    );
  }
}
