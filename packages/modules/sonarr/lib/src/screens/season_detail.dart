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
import 'season_progress.dart';
import 'sonarr_controllers.dart';
import 'sonarr_sources.dart';

/// The episodes of one season.
///
/// A season is no item of its own, so it has no detail slots: they are on the
/// screens of its series and of its episodes.
class SeasonScreen extends ConsumerWidget {
  /// Creates a [SeasonScreen] of season [number] of the series [seriesId].
  const SeasonScreen({
    required this.sources,
    required this.seriesId,
    required this.number,
    super.key,
  });

  /// The instance's.
  final SonarrSources sources;

  /// The series.
  final int seriesId;

  /// The season; 0 holds specials.
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = SonarrLocalizations.of(context);
    final series = sources.series(seriesId);
    final key = (sources, series);
    final state = ref.watch(episodesProvider(key));
    final known = switch (ref.watch(seriesProvider(key))) {
      ViewData(:final value) => value,
      ViewLoading() || ViewError() => null,
    };

    Future<void> refresh() => Future.wait([
      ref.read(seriesProvider(key).notifier).refresh(),
      ref.read(episodesProvider(key).notifier).refresh(),
    ]);

    bool ofSeason(Episode episode) => episode.seasonNumber == number;

    return DetailPage(
      title: seasonName(strings, number),
      onRefresh: refresh,
      body: StateScaffold<List<Episode>>(
        state: state,
        itemId: series,
        onRetry: () => unawaited(refresh()),
        isEmpty: (episodes) => !episodes.any(ofSeason),
        emptyMessage: strings.noEpisodes,
        builder: (context, all, {required isStale}) {
          final episodes = all.where(ofSeason).toList()
            ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
          final season = known?.seasons
              .where((season) => season.number == number)
              .firstOrNull;
          final title = known?.title ?? episodes.firstOrNull?.parentTitle;
          return DetailScroll(
            slivers: [
              SliverList.list(
                children: [
                  const SizedBox(height: 16),
                  if (title != null)
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                  if (season != null) SeasonProgress(season: season),
                ],
              ),
              // Built as it scrolls into view: a season may hold hundreds.
              SliverList.builder(
                itemCount: episodes.length,
                itemBuilder: (context, index) =>
                    _EpisodeRow(episode: episodes[index]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode});

  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final strings = SonarrLocalizations.of(context);
    final file = episode.file;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        strings.numberedEpisode(
          episode.episodeNumber,
          episodeTitle(strings, episode),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (episode.airDateUtc case final aired?)
            Text(formatDay(context, aired)),
          ItemStateLine(episode.state),
          if (!episode.monitored && episode.state != ItemState.unmonitored)
            const MonitoredLine(monitored: false),
          if (file != null)
            Text(
              [
                ?file.quality?.name,
                if (file.size > 0) formatBytes(context, file.size),
              ].join(strings.separator),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          unawaited(context.push<void>(itemRoute(episode.ref).location)),
    );
  }
}
