import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'library_source.dart';
import 'library_state.dart';

/// What there is to say about the instances above their items: which of them
/// failed, how old saved data is, and which are still loading. Each instance
/// that failed is named on its own, with its own retry.
class LibraryNotices extends StatelessWidget {
  const LibraryNotices({required this.state, required this.onRetry, super.key});

  final LibraryState state;

  /// Loads one instance again.
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) {
    final several = state.sources.length > 1;
    final shown = state.shown;
    final refreshing = [
      for (final source in shown)
        if (source.isLoading && source.fetchedAt != null) source,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One notice for all saved data that is being refreshed.
        if (refreshing.isNotEmpty)
          StaleNotice(
            key: const ValueKey('refreshing'),
            source: several && refreshing.length == 1
                ? refreshing.single.name
                : null,
            staleness: Staleness(fetchedAt: _oldest(refreshing)),
            // Not offered while it is under way.
            onRetry: () {},
          ),
        for (final source in shown)
          if (source.failure case final failure? when !source.isLoading)
            if (source.fetchedAt case final fetchedAt?)
              StaleNotice(
                key: ValueKey('stale ${source.id}'),
                source: several ? source.name : null,
                staleness: Staleness(fetchedAt: fetchedAt, failure: failure),
                onRetry: () => onRetry(source.id),
              )
            else
              _FailureNotice(
                key: ValueKey('failed ${source.id}'),
                name: several ? source.name : null,
                failure: failure,
                onRetry: () => onRetry(source.id),
              )
          else if (several && source.isLoading && source.entries == null)
            _LoadingNotice(
              key: ValueKey('loading ${source.id}'),
              name: source.name,
            ),
      ],
    );
  }

  static DateTime _oldest(List<LibrarySource> sources) => sources
      .map((source) => source.fetchedAt!)
      .reduce((a, b) => a.isBefore(b) ? a : b);
}

/// An instance that has nothing to show.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({
    required this.failure,
    required this.onRetry,
    this.name,
    super.key,
  });

  final String? name;
  final ServiceFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenMargin(constraints.maxWidth),
            vertical: 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name case final name?)
                      Text(name, style: theme.textTheme.titleSmall),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingNotice extends StatelessWidget {
  const _LoadingNotice({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenMargin(constraints.maxWidth),
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(AppLocalizations.of(context).libraryLoadingService(name)),
          const SizedBox(height: 4),
          const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}
