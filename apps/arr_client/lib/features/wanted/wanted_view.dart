import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../calendar/calendar_tiles.dart' show CalendarNote, openItem;
import 'wanted_controller.dart';
import 'wanted_search.dart';
import 'wanted_tile.dart';

/// One wanted list: a part for each service, in the user's order, each in its
/// server's own order. The orders differ (movies by title, episodes latest
/// aired first) and the lists arrive a page at a time, so they are not mixed.
class WantedView extends ConsumerStatefulWidget {
  const WantedView({required this.kind, super.key});

  final WantedKind kind;

  @override
  ConsumerState<WantedView> createState() => _WantedViewState();
}

class _WantedViewState extends ConsumerState<WantedView>
    with AutomaticKeepAliveClientMixin {
  /// Null while not selecting.
  Set<ItemRef>? _selected;

  // So that the pages read and the selection last while the other tab shows.
  @override
  bool get wantKeepAlive => true;

  void _select(Set<ItemRef>? selected) => setState(() => _selected = selected);

  void _toggle(ItemRef item) {
    final selected = {...?_selected};
    if (!selected.remove(item)) selected.add(item);
    _select(selected);
  }

  void _reload(String instanceId) {
    if (mounted) {
      unawaited(
        ref.read(wantedProvider(widget.kind).notifier).reload(instanceId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final strings = AppLocalizations.of(context);
    final lists = ref.watch(wantedProvider(widget.kind));
    final controller = ref.read(wantedProvider(widget.kind).notifier);
    final scope = ref.watch(scopeProvider);
    final sending = ref.watch(wantedSearchesProvider);

    if (lists == null) {
      return Center(
        child: CircularProgressIndicator(
          semanticsLabel: UiLocalizations.of(context).loading,
        ),
      );
    }
    if (lists.isEmpty) {
      return StateMessage(
        icon: Icons.bookmark_border_outlined,
        message: strings.notOffered,
      );
    }

    // What each instance can be asked to search for, of what is listed.
    final batches = <SearchBatch>[
      for (final list in lists)
        if (scope?.instance(list.instanceId) case final instance?)
          (
            instance: instance,
            items: searchable(instance, list.read?.items ?? const []),
          ),
    ];
    final offered = {
      for (final batch in batches)
        for (final item in batch.items) item.ref,
    };
    // What is no longer listed is no longer selected.
    final selected = offered.isEmpty ? null : _selected?.intersection(offered);
    final chosen = <SearchBatch>[
      for (final (:instance, :items) in batches)
        if ([
              for (final item in items)
                if (selected?.contains(item.ref) ?? false) item,
            ]
            case final own when own.isNotEmpty)
          (instance: instance, items: own),
    ];
    final canSearchChosen =
        chosen.isNotEmpty &&
        chosen.every((batch) => !sending.contains(batch.instance.instance.id));

    final rows = <Widget>[
      if (offered.isNotEmpty)
        _SelectionBar(
          count: selected?.length,
          onSelect: () => _select({}),
          onCancel: () => _select(null),
          onSearch: canSearchChosen
              ? () => unawaited(
                  searchWanted(
                    this.context,
                    ref,
                    chosen,
                    onSent: () => _select(null),
                    onRefresh: _reload,
                  ),
                )
              : null,
        ),
    ];

    for (final list in lists) {
      final id = list.instanceId;
      final instance = scope?.instance(id);
      final busy = sending.contains(id);
      final read = list.read;
      final failure = list.failure;
      final fetchedAt = list.fetchedAt;
      rows.add(
        _ServiceHeader(
          name: list.name,
          showSearchAll:
              selected == null &&
              instance?.capability(CapabilityKind.command) != null &&
              (read?.items.isNotEmpty ?? false),
          onSearchAll: busy || instance == null
              ? null
              : () => unawaited(
                  searchAllWanted(
                    this.context,
                    ref,
                    instance,
                    widget.kind,
                    onRefresh: _reload,
                  ),
                ),
        ),
      );
      if (busy) {
        rows.add(
          LinearProgressIndicator(
            semanticsLabel: strings.wantedSending(list.name),
          ),
        );
      }
      if (failure != null) {
        void retry() => unawaited(controller.retry(id));
        rows.add(
          read != null && fetchedAt != null
              ? StaleNotice(
                  staleness: Staleness(fetchedAt: fetchedAt, failure: failure),
                  onRetry: retry,
                )
              : _Failed(name: list.name, failure: failure, onRetry: retry),
        );
      }
      if (read != null) {
        if (read.items.isEmpty && failure == null) {
          rows.add(
            CalendarNote(switch (widget.kind) {
              WantedKind.missing => strings.wantedNoneMissing,
              WantedKind.cutoffUnmet => strings.wantedNoneCutoff,
            }),
          );
        }
        for (final item in read.items) {
          rows.add(
            WantedTile(
              key: ValueKey(item.ref),
              item: item,
              kind: widget.kind,
              selected: selected?.contains(item.ref),
              canSearch: offered.contains(item.ref),
              onToggle: () => _toggle(item.ref),
              onOpen: () => openItem(context, ref, item.ref, item.title),
              onSearch: busy || instance == null
                  ? null
                  : () => unawaited(
                      searchWanted(this.context, ref, [
                        (instance: instance, items: [item]),
                      ], onRefresh: _reload),
                    ),
            ),
          );
        }
      }
      if (list.loading) {
        rows.add(
          Padding(
            padding: const EdgeInsets.all(16),
            child: LinearProgressIndicator(
              semanticsLabel: strings.wantedLoading(list.name),
            ),
          ),
        );
      } else if (read != null && read.hasMore) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: OutlinedButton(
                onPressed: () => unawaited(controller.loadMore(id)),
                child: Text(
                  strings.wantedShowMore,
                  semanticsLabel: strings.wantedShowMoreOf(list.name),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Back leaves the selection before it leaves the screen.
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(null);
      },
      child: RefreshIndicator(
        onRefresh: controller.reload,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onSelect,
    required this.onCancel,
    required this.onSearch,
  });

  /// How many are selected; null while not selecting.
  final int? count;

  final VoidCallback onSelect;
  final VoidCallback onCancel;

  /// Null while the selection cannot be searched for.
  final VoidCallback? onSearch;

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
                  child: Text(strings.wantedSelect),
                ),
              ]
            : [
                Semantics(
                  liveRegion: true,
                  child: Text(strings.wantedSelectedCount(count)),
                ),
                TextButton(
                  onPressed: onCancel,
                  child: Text(UiLocalizations.of(context).cancel),
                ),
                FilledButton.tonal(
                  onPressed: onSearch,
                  child: Text(strings.wantedSearchSelected),
                ),
              ],
      ),
    );
  }
}

/// The name of a service above its items, with the search for all of them.
class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({
    required this.name,
    required this.showSearchAll,
    required this.onSearchAll,
  });

  final String name;
  final bool showSearchAll;
  final VoidCallback? onSearchAll;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final margin = screenMargin(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 16, margin, 4),
      // The button goes below the name where there is no room beside it.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Semantics(
              header: true,
              child: Text(name, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (showSearchAll)
              OutlinedButton(
                onPressed: onSearchAll,
                child: Text(
                  strings.wantedSearchAll,
                  semanticsLabel: strings.wantedSearchAllOf(name),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// That a service gave nothing, and why.
class _Failed extends StatelessWidget {
  const _Failed({
    required this.name,
    required this.failure,
    required this.onRetry,
  });

  final String name;
  final ServiceFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final margin = screenMargin(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(failureMessage(context, failure)),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onRetry,
              child: Text(
                UiLocalizations.of(context).retry,
                semanticsLabel: AppLocalizations.of(context)
                    .wantedRetryService(name),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
