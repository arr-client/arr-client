/// The words and icons of what the screens show.
library;

import 'package:core/core.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/generated/lidarr_localizations.dart';

/// The server's album types in the order its own pages list them.
const _albumTypes = ['Album', 'EP', 'Single', 'Broadcast', 'Other'];

/// The type an album is listed under: the server's, or `Other` without one.
String albumTypeOf(Album album) => album.albumType ?? 'Other';

/// Orders album types: those the server is known to have first.
int compareAlbumTypes(String a, String b) {
  int place(String type) {
    final index = _albumTypes.indexOf(type);
    return index < 0 ? _albumTypes.length : index;
  }

  final order = place(a).compareTo(place(b));
  return order != 0 ? order : a.compareTo(b);
}

/// The name of an album type. One the app does not know is the server's word.
String albumTypeLabel(LidarrLocalizations strings, String type) =>
    switch (type) {
      'Album' => strings.typeAlbum,
      'EP' => strings.typeEp,
      'Single' => strings.typeSingle,
      'Broadcast' => strings.typeBroadcast,
      'Other' => strings.typeOther,
      _ => type,
    };

/// A track's title, which the server may not know.
String trackTitle(LidarrLocalizations strings, Track track) =>
    track.title.isEmpty ? strings.untitledTrack : track.title;

/// A track in its album's list. Its number is as printed, and may be missing.
String numberedTrack(LidarrLocalizations strings, Track track) {
  final title = trackTitle(strings, track);
  return track.trackNumber.isEmpty
      ? title
      : strings.numberedTrack(track.trackNumber, title);
}

/// A playing time as players write it, such as 4:05.
String trackLength(LidarrLocalizations strings, Duration duration) {
  final number = NumberFormat('0', strings.localeName);
  final twoDigits = NumberFormat('00', strings.localeName);
  return strings.length(
    number.format(duration.inMinutes),
    twoDigits.format(duration.inSeconds % 60),
  );
}

/// What a history event was.
({String label, IconData icon}) eventLook(
  LidarrLocalizations strings,
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
