import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/sonarr_localizations.dart';
import '../sonarr_routes.dart';
import 'detail_parts.dart';
import 'labels.dart';
import 'season_progress.dart';
import 'sonarr_controllers.dart';
import 'sonarr_sources.dart';

/// A series: what it is, how far each season is, and what happened to it.
class SeriesDetailScreen extends ConsumerWidget {
  /// Creates a [SeriesDetailScreen] of the series [seriesId].
  const SeriesDetailScreen({
    required this.sources,
    required this.seriesId,
    super.key,
  });

  /// The instance's.
  final SonarrSources sources;

  /// The series.
  final int seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = sources.series(seriesId);
    final key = (sources, item);
    final state = ref.watch(seriesProvider(key));
    // Read from here, so that the seasons open at once and their episodes are
    // saved for offline use.
    ref.listen(episodesProvider(key), (_, _) {});

    Future<void> refresh() async {
      ref
        ..invalidate(historyProvider(key))
        ..invalidate(optionsProvider(sources));
      await Future.wait([
        ref.read(seriesProvider(key).notifier).refresh(),
        ref.read(episodesProvider(key).notifier).refresh(),
      ]);
    }

    return DetailPage(
      title: switch (state) {
        ViewData(:final value) => value.title,
        ViewLoading() || ViewError() => '',
      },
      onRefresh: refresh,
      body: StateScaffold<Series>(
        state: state,
        itemId: item,
        onRetry: () => unawaited(refresh()),
        builder: (context, series, {required isStale}) =>
            _SeriesBody(sources: sources, series: series),
      ),
    );
  }
}

class _SeriesBody extends ConsumerWidget {
  const _SeriesBody({required this.sources, required this.series});

  final SonarrSources sources;
  final Series series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = SonarrLocalizations.of(context);
    final key = (sources, series.ref);
    final options =
        ref.watch(optionsProvider(sources)).value ?? const <ServerOption>[];
    final history = ref.watch(historyProvider(key));
    final episodes = switch (ref.watch(episodesProvider(key))) {
      ViewData(:final value) => {
        for (final episode in value) episode.ref: episode,
      },
      ViewLoading() || ViewError() => const <ItemRef, Episode>{},
    };
    // As the server's own pages list them: the newest first, specials last.
    final seasons = [...series.seasons]
      ..sort((a, b) => b.number.compareTo(a.number));
    final overview = series.overview;

    return DetailScroll(
      slivers: [
        SliverList.list(
          children: [
            _Header(sources: sources, series: series),
            DetailSlot(DetailSlotName.downloadProgress, item: series.ref),
            if (overview != null && overview.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(overview),
            ],
            DetailSlot(DetailSlotName.subtitles, item: series.ref),
            SectionTitle(strings.details),
            FactList(_facts(strings, options)),
            SectionTitle(strings.seasons),
            if (seasons.isEmpty) Text(strings.noSeasons),
          ],
        ),
        SliverList.builder(
          itemCount: seasons.length,
          itemBuilder: (context, index) =>
              _SeasonRow(series: series.ref, season: seasons[index]),
        ),
        SliverToBoxAdapter(
          child: HistorySection(
            history: history.value,
            isLoading: history.isLoading,
            onRetry: () => ref.invalidate(historyProvider(key)),
            onShowAll: () =>
                unawaited(sources.navigator.openHistory(series.ref)),
            episodeOf: (item) => switch (episodes[item]) {
              final episode? => episodeCode(strings, episode),
              null => null,
            },
          ),
        ),
      ],
    );
  }

  /// What the server gives; the rest is left out.
  List<(String, String)> _facts(
    SonarrLocalizations strings,
    List<ServerOption> options,
  ) {
    String? option(ServerOptionKind kind, int id) => options
        .where((option) => option.kind == kind && option.id == id)
        .firstOrNull
        ?.label;
    final profile = switch (series.qualityProfileId) {
      final id? => option(ServerOptionKind.qualityProfile, id),
      null => null,
    };
    final tags = [
      for (final id in series.tagIds) ?option(ServerOptionKind.tag, id),
    ]..sort();
    final oneDecimal = NumberFormat.decimalPatternDigits(
      locale: strings.localeName,
      decimalDigits: 1,
    );
    String score(Rating rating) {
      final value = oneDecimal.format(rating.value);
      return [
        // Sonarr does not say whose score it is.
        if (rating.source.isEmpty)
          value
        else
          strings.ratingFrom(rating.source, value),
        if (rating.votes case final votes? when votes > 0) strings.votes(votes),
      ].join(strings.separator);
    }

    return [
      if (series.ratings.isNotEmpty)
        (strings.rating, series.ratings.map(score).join('\n')),
      if (series.genres.isNotEmpty)
        (strings.genres, series.genres.join(strings.listSeparator)),
      if (series.network case final network?) (strings.network, network),
      if (series.runtime case final runtime?)
        (strings.runtime, strings.minutes(runtime.inMinutes)),
      if (series.certification case final certification?)
        (strings.certification, certification),
      if (seriesTypeLabel(strings, series.seriesType) case final type?)
        (strings.seriesType, type),
      if (profile != null) (strings.qualityProfile, profile),
      if (tags.isNotEmpty) (strings.tags, tags.join(strings.listSeparator)),
      if (series.path case final path?) (strings.path, path),
    ];
  }
}

/// The artwork, title and where the series stands.
class _Header extends StatelessWidget {
  const _Header({required this.sources, required this.series});

  final SonarrSources sources;
  final Series series;

  @override
  Widget build(BuildContext context) {
    final strings = SonarrLocalizations.of(context);
    final theme = Theme.of(context);
    final facts = [
      if (series.year case final year?) '$year',
      ?statusLabel(strings, series.status),
    ];
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(series.title, style: theme.textTheme.headlineSmall),
        ),
        if (facts.isNotEmpty) Text(facts.join(strings.separator)),
        const SizedBox(height: 8),
        ItemStateLine(series.state),
        const SizedBox(height: 4),
        MonitoredLine(monitored: series.monitored),
        if (series.sizeOnDisk > 0) ...[
          const SizedBox(height: 4),
          Text(strings.sizeOnDisk(formatBytes(context, series.sizeOnDisk))),
        ],
      ],
    );
    final poster = Artwork(
      images: series.images,
      types: const [MediaImageType.poster],
      loader: sources.artwork,
      width: 112,
      aspectRatio: 2 / 3,
      placeholder: Icons.tv_outlined,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Beside the poster there must be room for the words.
        final beside =
            width - 128 >= MediaQuery.textScalerOf(context).scale(160);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Center(
              child: Artwork(
                images: series.images,
                types: const [MediaImageType.fanart, MediaImageType.banner],
                loader: sources.artwork,
                width: width < 480 ? width : 480,
                aspectRatio: 16 / 9,
              ),
            ),
            const SizedBox(height: 16),
            if (beside)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  poster,
                  const SizedBox(width: 16),
                  Expanded(child: title),
                ],
              )
            else ...[
              poster,
              const SizedBox(height: 16),
              title,
            ],
          ],
        );
      },
    );
  }
}

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({required this.series, required this.season});

  final ItemRef series;
  final Season season;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(seasonName(SonarrLocalizations.of(context), season.number)),
    subtitle: SeasonProgress(season: season),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => unawaited(
      context.push<void>(seasonRoute(series, season.number).location),
    ),
  );
}
