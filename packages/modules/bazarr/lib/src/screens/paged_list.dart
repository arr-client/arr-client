import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/bazarr_localizations.dart';
import 'list_controllers.dart';

/// A list read a page at a time, in each of its states, with a refresh and a
/// button for the next page.
class PagedList<T> extends StatelessWidget {
  /// Creates a [PagedList].
  const PagedList({
    required this.state,
    required this.controller,
    required this.emptyMessage,
    required this.row,
    required this.storageKey,
    super.key,
  });

  /// What was read.
  final ViewState<Pages<T>> state;

  /// Reads it.
  final PagedController<T> controller;

  /// Shown when the server lists nothing.
  final String emptyMessage;

  /// Builds one item.
  final Widget Function(T item) row;

  /// What the place in the list is kept under.
  final Object storageKey;

  @override
  Widget build(BuildContext context) {
    final strings = BazarrLocalizations.of(context);
    void refresh() => unawaited(controller.reload());
    return RefreshIndicator(
      onRefresh: controller.reload,
      child: StateScaffold<Pages<T>>(
        state: state,
        onRetry: refresh,
        isEmpty: (pages) => pages.items.isEmpty && !pages.hasMore,
        emptyMessage: emptyMessage,
        builder: (context, pages, {required isStale}) => LayoutBuilder(
          builder: (context, constraints) => ListView.separated(
            key: PageStorageKey(storageKey),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: screenMargin(constraints.maxWidth),
              vertical: 8,
            ),
            // The refresh button comes first and the next page last.
            itemCount: pages.items.length + 2,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                // Pulling down does this too, which a screen reader cannot.
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(strings.refresh),
                  ),
                );
              }
              if (index <= pages.items.length) {
                return row(pages.items[index - 1]);
              }
              return _Next(
                pages: pages,
                onMore: isStale ? null : () => unawaited(controller.loadMore()),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Next extends StatelessWidget {
  const _Next({required this.pages, required this.onMore});

  final Pages<Object?> pages;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    if (!pages.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (pages.moreFailure case final failure?)
            Semantics(
              liveRegion: true,
              child: Text(failureMessage(context, failure)),
            ),
          if (pages.loadingMore)
            LinearProgressIndicator(
              semanticsLabel: UiLocalizations.of(context).loading,
            )
          else
            OutlinedButton(
              onPressed: onMore,
              child: Text(BazarrLocalizations.of(context).showMore),
            ),
        ],
      ),
    );
  }
}
