import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'queue_controller.dart';

/// What there is to say about one instance's queue besides its entries: that
/// it is being read, could not be read, or is old.
class QueueInstanceNotice extends StatelessWidget {
  const QueueInstanceNotice({
    required this.queue,
    required this.onRetry,
    super.key,
  });

  /// One that has no entries yet, or stale ones.
  final InstanceQueue queue;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = queue.instance.instance.name;
    final failure = queue.failure;
    final fetchedAt = queue.fetchedAt;

    final Widget body;
    if (queue.items != null && fetchedAt != null) {
      body = StaleNotice(
        staleness: Staleness(fetchedAt: fetchedAt, failure: failure),
        onRetry: onRetry,
      );
    } else if (failure != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(failureMessage(context, failure)),
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
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LinearProgressIndicator(
          semanticsLabel: strings.queueLoading(name),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(name, style: theme.textTheme.titleSmall),
          ),
          body,
        ],
      ),
    );
  }
}
