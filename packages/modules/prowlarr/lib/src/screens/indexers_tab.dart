import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/prowlarr_localizations.dart';
import 'prowlarr_source.dart';
import 'search_controller.dart';

/// The indexers and what Prowlarr reports of their failures. Read only.
class IndexersTab extends ConsumerWidget {
  /// Creates an [IndexersTab].
  const IndexersTab({required this.source, super.key});

  /// Whose indexers.
  final ProwlarrSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ProwlarrLocalizations.of(context);
    final provider = indexersProvider(source);
    Future<void> refresh() => ref.read(provider.notifier).refresh();
    return RefreshIndicator(
      onRefresh: refresh,
      child: StateScaffold<List<Indexer>>(
        state: ref.watch(provider),
        onRetry: () => unawaited(refresh()),
        isEmpty: (indexers) => indexers.isEmpty,
        emptyMessage: strings.indexersNone,
        builder: (context, indexers, {required isStale}) => LayoutBuilder(
          builder: (context, constraints) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: screenMargin(constraints.maxWidth),
              vertical: 8,
            ),
            // The note comes first.
            itemCount: indexers.length + 1,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => index == 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.indexersNote),
                      // Pulling down does this too, which a screen reader
                      // cannot.
                      TextButton.icon(
                        onPressed: () => unawaited(refresh()),
                        icon: const Icon(Icons.refresh),
                        label: Text(strings.indexersRefresh),
                      ),
                    ],
                  )
                : _IndexerRow(indexers[index - 1]),
          ),
        ),
      ),
    );
  }
}

/// One indexer. What the server does not report is left out.
class _IndexerRow extends StatelessWidget {
  const _IndexerRow(this.indexer);

  final Indexer indexer;

  @override
  Widget build(BuildContext context) {
    final strings = ProwlarrLocalizations.of(context);
    final shared = UiLocalizations.of(context);
    final theme = Theme.of(context);
    final note = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final until = indexer.failureUntil;
    final paused = until != null && until.isAfter(DateTime.now());

    Widget warning(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: MediaQuery.textScalerOf(context).scale(16),
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (serverText(indexer.name) case final name?)
              Text(name, style: theme.textTheme.titleSmall),
            if (switch (indexer.protocol) {
                  DownloadProtocol.torrent => shared.releaseTorrent,
                  DownloadProtocol.usenet => shared.releaseUsenet,
                  DownloadProtocol.unknown => null,
                }
                case final protocol?)
              Text(protocol, style: note),
            if (indexer.enabled)
              Text(strings.indexerOn, style: note)
            else
              warning(Icons.block, strings.indexerOff),
            if (paused)
              warning(
                Icons.warning_amber,
                strings.indexerPaused(
                  formatDay(context, until),
                  formatTime(context, until),
                ),
              ),
            if (indexer.lastFailure case final failed?)
              Text(
                strings.indexerLastFailure(
                  formatDay(context, failed),
                  formatTime(context, failed),
                ),
                style: note,
              ),
          ],
        ),
      ),
    );
  }
}
