import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/bazarr_localizations.dart';
import '../subtitles_route.dart';
import 'labels.dart';
import 'read_controllers.dart';

/// The episodes of a series, with what each lacks.
class SubtitleSeriesScreen extends ConsumerWidget {
  /// Creates the screen of the series of [target].
  const SubtitleSeriesScreen({required this.target, super.key});

  /// The series.
  final MediaKey target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = BazarrLocalizations.of(context);
    final provider = episodesProvider(target);
    final name = ref.watch(seriesNameProvider(target)).value;
    Future<void> refresh() {
      ref.invalidate(seriesNameProvider(target));
      return ref.read(provider.notifier).reload();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(serverText(name) ?? strings.episodes),
        actions: [
          IconButton(
            tooltip: strings.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(refresh()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: StateScaffold<List<SubtitleTitle>>(
            state: ref.watch(provider),
            onRetry: () => unawaited(refresh()),
            itemId: target.media,
            isEmpty: (episodes) => episodes.isEmpty,
            emptyMessage: strings.seriesNoEpisodes,
            builder: (context, episodes, {required isStale}) => LayoutBuilder(
              builder: (context, constraints) => ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: screenMargin(constraints.maxWidth),
                  vertical: 8,
                ),
                itemCount: episodes.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(serverText(episode.title) ?? strings.untitled),
                    subtitle: Text(
                      [
                        if (episode.missing.isNotEmpty)
                          strings.missingLanguages(
                            languageList(strings, episode.missing),
                          ),
                        strings.fileCount(episode.files.length),
                      ].join('\n'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => unawaited(
                      context.push<void>(
                        mediaRoute(
                          target.source.instanceId,
                          episode.media,
                        ).location,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
