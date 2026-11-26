import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'client_progress_lines.dart';
import 'queue_labels.dart';

/// What a row of the queue says below the title.
class QueueEntrySummary extends StatelessWidget {
  const QueueEntrySummary({
    required this.item,
    this.instanceName,
    this.clientProgress,
    super.key,
  });

  final QueueItem item;

  /// Whose it is, where more than one queue is shown.
  final String? instanceName;

  /// What the download client says, where it has the download.
  final ClientProgressLines? clientProgress;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (icon, color) = queueSeverityIcon(theme.colorScheme, item.severity);
    final severity = queueSeverityLabel(strings, item.severity);
    final waiting = isWaitingRelease(item);
    final percent = queuePercent(context, item.progress);
    final amounts = [
      if (!waiting) percent,
      if (!waiting && item.sizeLeft > 0)
        strings.queueSizeLeft(formatBytes(context, item.sizeLeft)),
      ?queueTimeLabel(context, item),
    ];
    final source = [?item.quality?.name, ?item.downloadClient, ?instanceName];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [?severity, queueStateLabel(strings, item)].join(' · '),
              ),
            ),
          ],
        ),
        if (item.severity != QueueSeverity.ok)
          if (item.messages.firstOrNull case final message?)
            Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (!waiting) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: item.progress,
            semanticsLabel: strings.queueProgress,
            semanticsValue: percent,
          ),
          const SizedBox(height: 8),
        ],
        if (amounts.isNotEmpty) Text(amounts.join(' · ')),
        if (clientProgress case final lines?) ...[
          const SizedBox(height: 4),
          lines,
          const SizedBox(height: 4),
        ],
        if (source.isNotEmpty) Text(source.join(' · ')),
      ],
    );
  }
}
