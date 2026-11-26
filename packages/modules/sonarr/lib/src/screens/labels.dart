/// The words and icons of what the screens show.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/generated/sonarr_localizations.dart';

/// Null for a status the app does not know, which is not shown.
String? statusLabel(SonarrLocalizations strings, SeriesStatus status) =>
    switch (status) {
      SeriesStatus.continuing => strings.statusContinuing,
      SeriesStatus.ended => strings.statusEnded,
      SeriesStatus.upcoming => strings.statusUpcoming,
      SeriesStatus.deleted => strings.statusDeleted,
      SeriesStatus.unknown => null,
    };

/// Null for a type the app does not know, which is not shown.
String? seriesTypeLabel(SonarrLocalizations strings, SeriesType type) =>
    switch (type) {
      SeriesType.standard => strings.typeStandard,
      SeriesType.daily => strings.typeDaily,
      SeriesType.anime => strings.typeAnime,
      SeriesType.unknown => null,
    };

/// "Season 2", or "Specials" for season 0.
String seasonName(SonarrLocalizations strings, int number) =>
    number == 0 ? strings.specials : strings.seasonNumber(number);

/// Where an episode stands in its series.
String episodeCode(SonarrLocalizations strings, Episode episode) =>
    episode.seasonNumber == 0
    ? strings.specialCode(episode.episodeNumber)
    : strings.episodeCode(episode.seasonNumber, episode.episodeNumber);

/// An episode's title, which the server may not know yet.
String episodeTitle(SonarrLocalizations strings, Episode episode) =>
    episode.title.isEmpty ? strings.untitledEpisode : episode.title;

/// What a history event was.
({String label, IconData icon}) eventLook(
  SonarrLocalizations strings,
  HistoryEventType type,
) => switch (type) {
  HistoryEventType.grabbed => (
    label: strings.eventGrabbed,
    icon: Icons.cloud_download_outlined,
  ),
  HistoryEventType.imported => (
    label: strings.eventImported,
    icon: Icons.download_done,
  ),
  HistoryEventType.failed => (
    label: strings.eventFailed,
    icon: Icons.error_outline,
  ),
  HistoryEventType.renamed => (
    label: strings.eventRenamed,
    icon: Icons.drive_file_rename_outline,
  ),
  HistoryEventType.deleted => (
    label: strings.eventDeleted,
    icon: Icons.delete_outline,
  ),
  HistoryEventType.other => (label: strings.eventOther, icon: Icons.history),
};
