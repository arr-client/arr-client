/// The words and icons of a queue entry.
library;

import 'package:core/core.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';

/// Whether the server is holding the release back and has downloaded nothing.
bool isWaitingRelease(QueueItem item) =>
    (item.downloadId?.isEmpty ?? true) &&
    switch (item.status) {
      QueueStatus.delayed ||
      QueueStatus.downloadClientUnavailable ||
      QueueStatus.fallback => true,
      _ => false,
    };

/// The entry's title, or a stand-in where the server gives none.
String queueTitle(AppLocalizations strings, QueueItem item) =>
    item.title.isEmpty ? strings.queueUntitled : item.title;

/// The state of the entry: how far the server is with handling it where that
/// says more than the download's own status.
String queueStateLabel(AppLocalizations strings, QueueItem item) =>
    switch (item.trackedState) {
      TrackedState.importPending => strings.queueImportPending,
      TrackedState.importBlocked => strings.queueImportBlocked,
      TrackedState.importing => strings.queueImporting,
      TrackedState.imported => strings.queueImported,
      TrackedState.failedPending => strings.queueFailedPending,
      TrackedState.failed => strings.queueFailed,
      TrackedState.ignored => strings.queueIgnored,
      TrackedState.downloading || TrackedState.unknown => switch (item.status) {
        QueueStatus.queued => strings.queueQueued,
        QueueStatus.paused => strings.queuePaused,
        QueueStatus.downloading => strings.queueDownloading,
        QueueStatus.delayed => strings.queueDelayed,
        QueueStatus.completed => strings.queueCompleted,
        QueueStatus.warning => strings.queueWarning,
        QueueStatus.failed => strings.queueFailed,
        QueueStatus.downloadClientUnavailable => strings.queueClientUnavailable,
        QueueStatus.fallback => strings.queueFallback,
        QueueStatus.unknown => strings.queueStateUnknown,
      },
    };

/// What to call the severity; null where there is nothing to say.
String? queueSeverityLabel(AppLocalizations strings, QueueSeverity severity) =>
    switch (severity) {
      QueueSeverity.ok => null,
      QueueSeverity.warning => strings.queueSeverityWarning,
      QueueSeverity.error => strings.queueSeverityError,
      QueueSeverity.unknown => strings.queueSeverityUnknown,
    };

/// An icon for [severity], and its colour in [scheme].
(IconData, Color) queueSeverityIcon(
  ColorScheme scheme,
  QueueSeverity severity,
) => switch (severity) {
  QueueSeverity.ok => (Icons.download_outlined, scheme.onSurfaceVariant),
  QueueSeverity.warning => (Icons.warning_amber_outlined, scheme.tertiary),
  QueueSeverity.error => (Icons.error_outline, scheme.error),
  QueueSeverity.unknown => (Icons.help_outline, scheme.onSurfaceVariant),
};

/// How it is downloaded; null if the app does not know.
String? queueProtocolLabel(
  AppLocalizations strings,
  DownloadProtocol protocol,
) => switch (protocol) {
  DownloadProtocol.torrent => strings.queueTorrent,
  DownloadProtocol.usenet => strings.queueUsenet,
  DownloadProtocol.unknown => null,
};

/// [progress], from 0 to 1, as the viewer writes a percentage. It is rounded
/// down, so that 100% means all of it.
String queuePercent(BuildContext context, double progress) =>
    NumberFormat.percentPattern(Localizations.localeOf(context).toString())
        .format((progress * 100).floor() / 100);

/// The time the server expects: until the download ends, or until it grabs a
/// release it holds back. Null where it does not say.
String? queueTimeLabel(BuildContext context, QueueItem item) {
  final eta = item.eta;
  if (eta == null) return null;
  final strings = AppLocalizations.of(context);
  final time = formatDuration(context, eta);
  return isWaitingRelease(item)
      ? strings.queueGrabbedIn(time)
      : strings.queueTimeLeft(time);
}
