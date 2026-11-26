import 'dart:async';

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'import_file.dart';
import 'import_labels.dart';
import 'import_pickers.dart';
import 'manual_import_controller.dart';

/// One file: whether it is imported, what the server takes it for, and the
/// ways to correct that.
class ImportFileTile extends StatelessWidget {
  const ImportFileTile({
    required this.file,
    required this.state,
    required this.controller,
    super.key,
  });

  final ImportFile file;
  final ManualImportState state;
  final ManualImportController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final candidate = file.candidate;
    final match = candidate.matchedRef;
    final series = state.needsEpisodes;
    final ready = state.isReady(candidate);
    final editable = state.canChange && !file.checking;
    final items = state.items;
    final episodes = match == null ? null : state.episodes[match.remoteId];
    final choices = state.choices;

    // Why it cannot be selected.
    final missing = ready
        ? null
        : match == null
        ? series
              ? strings.manualImportNeedsSeries
              : strings.manualImportNeedsMovie
        : series && candidate.episodeIds.isEmpty
        ? strings.manualImportNeedsEpisodes
        : strings.manualImportNeedsNames;

    Widget fact(String label, String value, Future<void> Function()? correct) =>
        ListTile(
          title: Text(label, style: theme.textTheme.labelMedium),
          subtitle: Text(value, style: theme.textTheme.bodyLarge),
          trailing: correct == null ? null : const Icon(Icons.edit_outlined),
          onTap: correct == null ? null : () => unawaited(correct()),
        );

    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Semantics(liveRegion: true, child: Text(text)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: file.selected,
          onChanged: ready && editable
              ? (value) => controller.select(file.path, value ?? false)
              : null,
          title: Text(file.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (candidate.size > 0)
                Text(formatBytes(context, candidate.size)),
              Text(file.path, style: theme.textTheme.bodySmall),
              ?(missing == null ? null : Text(missing)),
            ],
          ),
        ),
        fact(
          series ? strings.manualImportSeries : strings.manualImportMovie,
          importMatchLabel(strings, state, candidate),
          !editable || items == null
              ? null
              : () async {
                  final chosen = await pickImportItem(
                    context,
                    title: series
                        ? strings.manualImportChooseSeries
                        : strings.manualImportChooseMovie,
                    items: items,
                    current: match,
                  );
                  if (chosen == null || chosen == match || !context.mounted) {
                    return;
                  }
                  await controller.correct(file.path, matchedRef: chosen);
                },
        ),
        if (series)
          fact(
            strings.manualImportEpisodes,
            importEpisodesLabel(strings, state, candidate),
            !editable || episodes == null
                ? null
                : () async {
                    final chosen = await pickImportEpisodes(
                      context,
                      episodes: episodes,
                      current: candidate.episodeIds,
                    );
                    if (chosen == null || !context.mounted) return;
                    await controller.correct(file.path, episodeIds: chosen);
                  },
          ),
        fact(
          strings.manualImportQuality,
          importQualityLabel(strings, candidate),
          !editable || choices == null || choices.qualities.isEmpty
              ? null
              : () async {
                  final chosen = await pickImportQuality(
                    context,
                    qualities: choices.qualities,
                    current: candidate.quality,
                  );
                  if (chosen == null ||
                      chosen.id == candidate.quality?.id ||
                      !context.mounted) {
                    return;
                  }
                  await controller.correct(file.path, quality: chosen);
                },
        ),
        // Not every service lets the language be corrected.
        if (candidate.languages.isNotEmpty ||
            (choices?.languages.isNotEmpty ?? false))
          fact(
            strings.manualImportLanguages,
            importLanguagesLabel(strings, candidate),
            !editable || choices == null || choices.languages.isEmpty
                ? null
                : () async {
                    final chosen = await pickImportLanguages(
                      context,
                      languages: choices.languages,
                      current: candidate.languages,
                    );
                    if (chosen == null ||
                        _same(chosen, candidate.languages) ||
                        !context.mounted) {
                      return;
                    }
                    await controller.correct(file.path, languages: chosen);
                  },
          ),
        if (candidate.rejections.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.manualImportRejected),
                      for (final rejection in candidate.rejections)
                        Text(rejection),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (file.checking)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: LinearProgressIndicator(
              semanticsLabel: strings.manualImportChecking,
            ),
          )
        else if (file.checkFailure case final failure?)
          note(
            '${strings.manualImportCheckFailed}\n'
            '${failureMessage(context, failure)}',
          )
        else if (file.unchecked)
          note(strings.manualImportUnchecked),
        if (file.episodesDropped) note(strings.manualImportEpisodesDropped),
        const Divider(),
      ],
    );
  }

  static bool _same(List<Language> a, List<Language> b) =>
      a.length == b.length &&
      a.every((language) => b.any((other) => other.id == language.id));
}
