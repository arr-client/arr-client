import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'history_event_tile.dart';
import 'item_history_controller.dart';

/// The whole history of one item, newest first, a page at a time.
class ItemHistoryScreen extends ConsumerWidget {
  const ItemHistoryScreen({
    required this.instance,
    required this.item,
    super.key,
  });

  /// The instance that holds the item.
  final ActiveInstance instance;

  final ItemRef item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    if (instance.capability(CapabilityKind.history) == null) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.itemHistory)),
        body: SafeArea(
          child: StateMessage(
            icon: Icons.info_outline,
            message: strings.notOffered,
          ),
        ),
      );
    }

    final provider = itemHistoryProvider((
      item: item,
      client: instance.context.http,
    ));
    final history = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final events = history.events;
    final fetchedAt = history.fetchedAt;
    final failure = history.failure;
    final ViewState<List<HistoryEvent>> view;
    if (events != null && fetchedAt != null) {
      view = ViewData(
        events,
        // While it is read again after a failure, the notice shows progress.
        staleness: failure == null
            ? null
            : Staleness(
                fetchedAt: fetchedAt,
                failure: history.refreshing ? null : failure,
              ),
      );
    } else if (failure != null && !history.refreshing) {
      view = ViewError(failure);
    } else {
      view = const ViewLoading();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.itemHistory),
        actions: [
          // Pulling down does this too, which a screen reader cannot.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.historyRefresh,
            onPressed: history.refreshing
                ? null
                : () => unawaited(controller.retry()),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.retry,
          child: StateScaffold<List<HistoryEvent>>(
            state: view,
            itemId: item,
            onGone: () => unawaited(
              instance.context.cache.remove(item.kind, item.remoteId),
            ),
            onRetry: () => unawaited(controller.retry()),
            isEmpty: (events) => events.isEmpty && !history.hasMore,
            emptyMessage: strings.historyEmpty,
            builder: (context, events, {required isStale}) => _Events(
              events: events,
              history: history,
              canReadOlder: !isStale && !history.refreshing,
              onOlder: () => unawaited(controller.loadMore()),
              onRetryOlder: () => unawaited(controller.retry(older: true)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Events extends StatelessWidget {
  const _Events({
    required this.events,
    required this.history,
    required this.canReadOlder,
    required this.onOlder,
    required this.onRetryOlder,
  });

  final List<HistoryEvent> events;
  final ItemHistoryState history;

  /// Not while the events shown may be replaced.
  final bool canReadOlder;

  final VoidCallback onOlder;
  final VoidCallback onRetryOlder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: screenMargin(constraints.maxWidth),
        vertical: 8,
      ),
      itemCount: events.length + (history.hasMore ? 1 : 0),
      itemBuilder: (context, index) => index < events.length
          ? HistoryEventTile(events[index], key: ValueKey(events[index].id))
          : _older(context),
    ),
  );

  /// What follows the events while the server has older ones.
  Widget _older(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (history.loadingMore) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CircularProgressIndicator(
            semanticsLabel: UiLocalizations.of(context).loading,
          ),
        ),
      );
    }
    if (history.moreFailure case final failure?) {
      return Column(
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              '${strings.historyOlderFailed}\n'
              '${failureMessage(context, failure)}',
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: canReadOlder ? onRetryOlder : null,
            child: Text(strings.historyRetryOlder),
          ),
        ],
      );
    }
    return Center(
      child: TextButton(
        onPressed: canReadOlder ? onOlder : null,
        child: Text(strings.historyShowOlder),
      ),
    );
  }
}
