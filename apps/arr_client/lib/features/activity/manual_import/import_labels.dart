/// The words for what a file is matched to.
library;

import 'package:core/core.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'manual_import_controller.dart';

/// A movie or series, with its year where the server gives one.
String importItemLabel(AppLocalizations strings, LibraryItem item) =>
    switch (item.year) {
      final year? when year > 0 => strings.manualImportTitleYear(
        item.title,
        '$year',
      ),
      _ => item.title,
    };

String importEpisodeLabel(AppLocalizations strings, Episode episode) =>
    strings.manualImportEpisode(
      '${episode.seasonNumber}'.padLeft(2, '0'),
      '${episode.episodeNumber}'.padLeft(2, '0'),
      episode.title,
    );

String importSeasonLabel(AppLocalizations strings, int number) => number == 0
    ? strings.manualImportSpecials
    : strings.manualImportSeason(number);

/// What [candidate] is matched to, as far as it can be named.
String importMatchLabel(
  AppLocalizations strings,
  ManualImportState state,
  ManualImportCandidate candidate,
) {
  final match = candidate.matchedRef;
  if (match == null) return strings.manualImportNotMatched;
  final item = state.item(match);
  return item == null
      ? strings.manualImportNameMissing
      : importItemLabel(strings, item);
}

/// The episodes of [candidate], one to a line.
String importEpisodesLabel(
  AppLocalizations strings,
  ManualImportState state,
  ManualImportCandidate candidate,
) {
  final series = candidate.matchedRef;
  if (series == null || candidate.episodeIds.isEmpty) {
    return strings.manualImportNoEpisodes;
  }
  return [
    for (final id in candidate.episodeIds)
      if (state.episode(series, id) case final episode?)
        importEpisodeLabel(strings, episode)
      else
        strings.manualImportNameMissing,
  ].join('\n');
}

String importQualityLabel(
  AppLocalizations strings,
  ManualImportCandidate candidate,
) => candidate.quality?.name ?? strings.manualImportUnknownValue;

String importLanguagesLabel(
  AppLocalizations strings,
  ManualImportCandidate candidate,
) => candidate.languages.isEmpty
    ? strings.manualImportUnknownValue
    : candidate.languages.map((language) => language.name).join(', ');
