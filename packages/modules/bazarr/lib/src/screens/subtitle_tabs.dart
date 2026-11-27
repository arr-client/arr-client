/// The wanted, history and browse tabs of the subtitle screen.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/bazarr_localizations.dart';
import '../subtitles_route.dart';
import 'bazarr_source.dart';
import 'labels.dart';
import 'list_controllers.dart';
import 'paged_list.dart';

/// What a tab lists.
enum SubtitleTab {
  /// What lacks subtitles.
  wanted,

  /// What the server did.
  history,

  /// The movies and series.
  browse,
}

/// One tab: a choice of movies or episodes, and their list.
class SubtitleTabView extends ConsumerStatefulWidget {
  /// Creates the view of [tab].
  const SubtitleTabView({required this.source, required this.tab, super.key});

  /// What is read.
  final BazarrSource source;

  /// Which list.
  final SubtitleTab tab;

  @override
  ConsumerState<SubtitleTabView> createState() => _SubtitleTabViewState();
}

class _SubtitleTabViewState extends ConsumerState<SubtitleTabView>
    with AutomaticKeepAliveClientMixin {
  var _type = SubtitleMediaType.movie;

  // So that the pages read are kept while another tab is shown.
  @override
  bool get wantKeepAlive => true;

  void _open(SubtitleMedia media) => unawaited(
    context.push<void>(mediaRoute(widget.source.instanceId, media).location),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final strings = BazarrLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: screenMargin(constraints.maxWidth),
              vertical: 4,
            ),
            child: Wrap(
              spacing: 8,
              children: [
                for (final type in [
                  SubtitleMediaType.movie,
                  SubtitleMediaType.episode,
                ])
                  ChoiceChip(
                    label: Text(switch (type) {
                      SubtitleMediaType.movie => strings.movies,
                      SubtitleMediaType.episode
                          when widget.tab == SubtitleTab.browse =>
                        strings.series,
                      SubtitleMediaType.episode => strings.episodes,
                    }),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
          ),
          Expanded(child: _list(strings)),
        ],
      ),
    );
  }

  Widget _list(BazarrLocalizations strings) {
    final key = (source: widget.source, type: _type);
    final storageKey = '${widget.tab.name} ${_type.name}';
    final movies = _type == SubtitleMediaType.movie;
    switch (widget.tab) {
      case SubtitleTab.wanted:
        final provider = wantedProvider(key);
        return PagedList<SubtitleWant>(
          state: ref.watch(provider),
          controller: ref.read(provider.notifier),
          storageKey: storageKey,
          emptyMessage: movies
              ? strings.wantedNoMovies
              : strings.wantedNoEpisodes,
          row: (want) => _Row(
            title: want.title,
            lines: [
              if (want.missing.isNotEmpty)
                strings.missingLanguages(languageList(strings, want.missing)),
            ],
            onTap: () => _open(want.media),
          ),
        );
      case SubtitleTab.history:
        final provider = historyProvider(key);
        return PagedList<SubtitleHistoryEvent>(
          state: ref.watch(provider),
          controller: ref.read(provider.notifier),
          storageKey: storageKey,
          emptyMessage: movies
              ? strings.historyNoMovies
              : strings.historyNoEpisodes,
          row: (event) => _Row(
            title: event.title,
            lines: [
              ?serverText(event.action),
              strings.historyLanguage(languageLabel(strings, event.language)),
              if (serverText(event.provider) case final provider?)
                strings.provider(provider),
              if (serverText(event.score) case final score?)
                strings.score(score),
              ?serverText(event.whenText),
            ],
            onTap: () => _open(event.mediaRef),
          ),
        );
      case SubtitleTab.browse:
        final provider = titlesProvider(key);
        return PagedList<SubtitleTitle>(
          state: ref.watch(provider),
          controller: ref.read(provider.notifier),
          storageKey: storageKey,
          emptyMessage: movies
              ? strings.browseNoMovies
              : strings.browseNoSeries,
          row: (title) {
            final name = serverText(title.title) ?? strings.untitled;
            return _Row(
              title: switch (title.year) {
                final year? => strings.titleWithYear(name, '$year'),
                null => name,
              },
              lines: [
                if (title.missingCount > 0)
                  strings.missingCount(title.missingCount),
              ],
              onTap: () => _open(title.media),
            );
          },
        );
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.lines, required this.onTap});

  final String title;
  final List<String> lines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(serverText(title) ?? BazarrLocalizations.of(context).untitled),
    subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
