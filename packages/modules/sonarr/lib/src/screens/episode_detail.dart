import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/sonarr_localizations.dart';
import '../sonarr_routes.dart';
import 'detail_parts.dart';
import 'labels.dart';
import 'sonarr_actions.dart';
import 'sonarr_actions_controller.dart';
import 'sonarr_controllers.dart';
import 'sonarr_sources.dart';

/// An episode, its file and what happened to it.
class EpisodeScreen extends ConsumerWidget {
  /// Creates an [EpisodeScreen] of the episode [episodeId].
  const EpisodeScreen({
    required this.sources,
    required this.episodeId,
    super.key,
  });

  /// The instance's.
  final SonarrSources sources;

  /// The episode.
  final int episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = SonarrLocalizations.of(context);
    final item = sources.episode(episodeId);
    final key = (sources, item);
    final state = ref.watch(episodeProvider(key));

    Future<void> refresh() {
      ref.invalidate(historyProvider(key));
      return ref.read(episodeProvider(key).notifier).refresh();
    }

    return SonarrActionsScope(
      sources: sources,
      target: MediaTarget(item),
      child: DetailPage(
        title: switch (state) {
          ViewData(:final value) => episodeCode(strings, value),
          ViewLoading() || ViewError() => '',
        },
        onRefresh: refresh,
        body: StateScaffold<Episode>(
          state: state,
          itemId: item,
          onRetry: () => unawaited(refresh()),
          builder: (context, episode, {required isStale}) => _EpisodeBody(
            sources: sources,
            episode: episode,
            isStale: isStale,
          ),
        ),
      ),
    );
  }
}

class _EpisodeBody extends ConsumerWidget {
  const _EpisodeBody({
    required this.sources,
    required this.episode,
    required this.isStale,
  });

  final SonarrSources sources;
  final Episode episode;
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = SonarrLocalizations.of(context);
    final theme = Theme.of(context);
    final key = (sources, episode.ref);
    final history = ref.watch(historyProvider(key));
    final series = episode.parent;
    final overview = episode.overview;
    final file = episode.file;
    final target = MediaTarget(episode.ref);
    final deleting = ref.watch(
      sonarrActionsProvider((sources, target))
          .select((state) => state.deletingFile),
    );
    // The screen's own context, which outlives the rows of the list.
    final screen = context;

    return DetailScroll(
      slivers: [
        SliverList.list(
          children: [
            const SizedBox(height: 16),
            if (series != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tv_outlined),
                title: Text(episode.parentTitle ?? strings.openSeries),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    unawaited(context.push<void>(itemRoute(series).location)),
              ),
            Semantics(
              header: true,
              child: Text(
                episodeTitle(strings, episode),
                style: theme.textTheme.headlineSmall,
              ),
            ),
            Text(episodeCode(strings, episode)),
            if (episode.airDateUtc case final aired?)
              Text(
                strings.airs(
                  strings.dateAndTime(
                    formatDay(context, aired),
                    formatTime(context, aired),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ItemStateLine(episode.state),
            const SizedBox(height: 8),
            SonarrActions(
              sources: sources,
              target: target,
              monitored: episode.monitored,
              isStale: isStale,
            ),
            DetailSlot(
              DetailSlotName.downloadProgress,
              item: episode.ref,
              parent: series,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Center(
                child: Artwork(
                  images: episode.images,
                  // Sonarr's screenshot of an episode has no type of its own.
                  types: const [MediaImageType.other],
                  loader: sources.artwork,
                  width: constraints.maxWidth < 480
                      ? constraints.maxWidth
                      : 480,
                  aspectRatio: 16 / 9,
                ),
              ),
            ),
            if (overview != null && overview.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(overview),
            ],
            DetailSlot(
              DetailSlotName.subtitles,
              item: episode.ref,
              parent: series,
            ),
            SectionTitle(strings.file),
            if (file == null)
              Text(strings.noFile)
            else ...[
              FactList(_fileFacts(context, strings, file)),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(strings.deleteFile),
                // Only a file the instance has just listed can be deleted.
                onPressed: isStale || deleting
                    ? null
                    : () => unawaited(
                        deleteEpisodeFile(screen, ref, sources, episode, file),
                      ),
              ),
            ],
            HistorySection(
              history: history.value,
              isLoading: history.isLoading,
              onRetry: () => ref.invalidate(historyProvider(key)),
              onShowAll: () =>
                  unawaited(sources.navigator.openHistory(episode.ref)),
            ),
          ],
        ),
      ],
    );
  }

  List<(String, String)> _fileFacts(
    BuildContext context,
    SonarrLocalizations strings,
    MediaFile file,
  ) => [
    if (file.quality case final quality?) (strings.quality, quality.name),
    if (file.size > 0) (strings.size, formatBytes(context, file.size)),
    if (file.languages.isNotEmpty)
      (
        strings.languages,
        file.languages
            .map((language) => language.name)
            .join(strings.listSeparator),
      ),
    if (file.video case final video?) (strings.video, video),
    if (file.audio case final audio?) (strings.audio, audio),
    (strings.path, file.path),
  ];
}
