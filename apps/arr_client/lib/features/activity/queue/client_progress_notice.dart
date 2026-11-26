import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';

/// Whether a download client could have [item], so that the lack of its figures
/// is worth telling.
bool expectsClientProgress(QueueItem item) =>
    (item.downloadId?.isNotEmpty ?? false) &&
    item.protocol != DownloadProtocol.usenet;

/// Says that a download client could not be read, so that only the servers'
/// own progress is shown.
class ClientProgressNotice extends StatelessWidget {
  const ClientProgressNotice({
    required this.client,
    required this.failure,
    required this.onRetry,
    super.key,
  });

  /// What to call the download client.
  final String client;

  final ServiceFailure failure;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.clientProgressUnavailable(client),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(failureMessage(context, failure)),
                ],
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onRetry,
                child: Text(UiLocalizations.of(context).retry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
