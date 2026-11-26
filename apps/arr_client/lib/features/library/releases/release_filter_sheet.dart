import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'release_view.dart';

/// Opens the filters of [releases]. Each choice applies to [view] at once.
Future<void> showReleaseFilters(
  BuildContext context, {
  required List<Release> releases,
  required ValueNotifier<ReleaseView> view,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => ValueListenableBuilder(
    valueListenable: view,
    builder: (context, value, _) => _FilterSheet(
      releases: releases,
      view: value,
      onChanged: (changed) => view.value = changed,
    ),
  ),
);

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.releases,
    required this.view,
    required this.onChanged,
  });

  final List<Release> releases;
  final ReleaseView view;
  final ValueChanged<ReleaseView> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);

    /// The chips of what the releases have, and of what is chosen, which can
    /// then still be taken off.
    List<Widget> choices<T>({
      required String title,
      required Iterable<T> found,
      required Set<T> chosen,
      required String Function(T value) label,
      required ReleaseView Function(Set<T> chosen) apply,
    }) {
      final values = {...found, ...chosen}.toList()
        ..sort((a, b) => label(a).compareTo(label(b)));
      if (values.isEmpty) return const [];
      return [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final value in values)
              FilterChip(
                label: Text(label(value)),
                selected: chosen.contains(value),
                onSelected: (on) => onChanged(
                  apply(on ? {...chosen, value} : chosen.difference({value})),
                ),
              ),
          ],
        ),
      ];
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = screenMargin(constraints.maxWidth);
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              margin,
              0,
              margin,
              16 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    strings.libraryFilters,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.releasesFilterHideRejected),
                  value: view.hideRejected,
                  onChanged: (on) => onChanged(view.copyWith(hideRejected: on)),
                ),
                ...choices<DownloadProtocol>(
                  title: strings.queueProtocol,
                  found: [
                    for (final release in releases)
                      if (release.protocol != DownloadProtocol.unknown)
                        release.protocol,
                  ],
                  chosen: view.protocols,
                  label: (protocol) => protocol == DownloadProtocol.usenet
                      ? strings.queueUsenet
                      : strings.queueTorrent,
                  apply: (chosen) => view.copyWith(protocols: chosen),
                ),
                ...choices<String>(
                  title: strings.releasesFilterIndexer,
                  found: [
                    for (final release in releases)
                      ?releaseIndexerName(release),
                  ],
                  chosen: view.indexers,
                  label: (name) => name,
                  apply: (chosen) => view.copyWith(indexers: chosen),
                ),
                ...choices<String>(
                  title: strings.releasesFilterQuality,
                  found: [
                    for (final release in releases)
                      ?releaseQualityName(release),
                  ],
                  chosen: view.qualities,
                  label: (name) => name,
                  apply: (chosen) => view.copyWith(qualities: chosen),
                ),
                ...choices<String>(
                  title: strings.releasesFilterLanguage,
                  found: [
                    for (final release in releases)
                      ...releaseLanguageNames(release),
                  ],
                  chosen: view.languages,
                  label: (name) => name,
                  apply: (chosen) => view.copyWith(languages: chosen),
                ),
                const SizedBox(height: 24),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [
                    TextButton(
                      onPressed: view.activeFilters == 0
                          ? null
                          : () => onChanged(
                              view.withoutFilters().copyWith(text: view.text),
                            ),
                      child: Text(strings.libraryClearFilters),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        strings.releasesShowResults(
                          view.apply(releases).length,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
