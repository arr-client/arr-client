import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'queue_labels.dart';

/// A download client's figures for the download of a queue entry, beside the
/// server's own.
class ClientProgressLines extends StatelessWidget {
  const ClientProgressLines({
    required this.progress,
    required this.client,
    required this.wholeDownload,
    super.key,
  });

  final DownloadProgress progress;

  /// What to call the download client.
  final String client;

  /// Whether other queue entries share the download, so that the figures are
  /// not this entry's alone.
  final bool wholeDownload;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    // In the other states nothing is expected to arrive, and a speed of nothing
    // says nothing.
    final showSpeed =
        progress.downSpeed > 0 ||
        progress.state == DownloadState.downloading ||
        progress.state == DownloadState.stalled;
    final amounts = [
      if (showSpeed) formatSpeed(context, progress.downSpeed),
      if (progress.eta case final eta?)
        strings.queueTimeLeft(formatDuration(context, eta)),
    ];
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              strings.clientProgressFrom(
                client,
                queuePercent(context, progress.progress),
              ),
              clientStateLabel(strings, progress.state),
            ].join(' · '),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (amounts.isNotEmpty) Text(amounts.join(' · ')),
          if (wholeDownload) Text(strings.clientProgressWholeDownload),
        ],
      ),
    );
  }
}
