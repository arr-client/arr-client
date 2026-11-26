import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'activity_feed.dart';

/// The words for reading older ones.
typedef OlderLabels = ({String show, String failed, String retry});

/// A combined list as one scroll view: [head], what there is to say about
/// single instances, the rows, and the way to older ones.
class FeedList<T> extends StatelessWidget {
  const FeedList({
    required this.feed,
    required this.rowBuilder,
    required this.controller,
    required this.emptyMessage,
    required this.older,
    this.head = const [],
    super.key,
  });

  final FeedState<T> feed;
  final Widget Function(FeedRow<T> row) rowBuilder;
  final ActivityFeed<T> controller;
  final String emptyMessage;
  final OlderLabels older;
  final List<Widget> head;

  @override
  Widget build(BuildContext context) {
    final sources = feed.sources;
    // Nothing from anyone yet.
    if (sources.every((s) => s.items == null && s.failure == null)) {
      return Center(
        child: CircularProgressIndicator(
          semanticsLabel: UiLocalizations.of(context).loading,
        ),
      );
    }
    final notices = [
      for (final source in sources)
        if (source.items == null || source.failure != null)
          _SourceNotice(
            key: ValueKey(('notice', source.id)),
            source: source,
            onRetry: () => unawaited(controller.retry(source.id)),
          ),
    ];
    final rows = feed.rows;
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = EdgeInsets.symmetric(
          horizontal: screenMargin(constraints.maxWidth),
        );
        Widget inset(Widget child) => Padding(padding: margin, child: child);
        final above = [...head, ...notices];
        final below = [
          if (rows.isEmpty && notices.isEmpty && feed.next.isEmpty)
            inset(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(emptyMessage, textAlign: TextAlign.center),
              ),
            ),
          for (final source in sources)
            if (source.moreFailure case final failure?)
              inset(
                Column(
                  key: ValueKey(('older', source.id)),
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        [
                          if (sources.length > 1) source.instance.instance.name,
                          older.failed,
                          failureMessage(context, failure),
                        ].join('\n'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: source.isStale
                          ? null
                          : () => unawaited(
                              controller.retry(source.id, older: true),
                            ),
                      child: Text(older.retry),
                    ),
                  ],
                ),
              ),
          if (sources.any((source) => source.loadingMore))
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  semanticsLabel: UiLocalizations.of(context).loading,
                ),
              ),
            )
          else if (feed.next.isNotEmpty)
            Center(
              child: TextButton(
                // Not while what is shown may be replaced.
                onPressed: feed.next.any((source) => source.refreshing)
                    ? null
                    : () => unawaited(controller.loadMore()),
                child: Text(older.show),
              ),
            ),
        ];
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: above.length + rows.length + below.length,
            itemBuilder: (context, index) {
              if (index < above.length) return above[index];
              final row = index - above.length;
              return row < rows.length
                  ? inset(rowBuilder(rows[row]))
                  : below[row - rows.length];
            },
          ),
        );
      },
    );
  }
}

/// That one instance's list is being read, could not be read, or is old.
class _SourceNotice<T> extends StatelessWidget {
  const _SourceNotice({required this.source, required this.onRetry, super.key});

  /// One that has nothing yet, or a failure.
  final FeedSource<T> source;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = source.instance.instance.name;
    final failure = source.failure;
    final fetchedAt = source.fetchedAt;

    if (source.items != null && fetchedAt != null) {
      return StaleNotice(
        source: name,
        staleness: Staleness(
          fetchedAt: fetchedAt,
          // While it is read again, the notice shows progress.
          failure: source.refreshing ? null : failure,
        ),
        onRetry: onRetry,
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: theme.textTheme.titleSmall),
            if (failure == null || source.refreshing)
              LinearProgressIndicator(
                semanticsLabel: strings.activityLoadingFrom(name),
              )
            else ...[
              Semantics(
                liveRegion: true,
                child: Text(failureMessage(context, failure)),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: onRetry,
                  child: Text(UiLocalizations.of(context).retry),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
