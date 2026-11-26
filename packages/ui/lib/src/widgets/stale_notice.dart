import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';
import 'failure_message.dart';
import 'screen_margin.dart';
import 'view_state.dart';

/// Marks the data below it as saved data: its age, and either why it could not
/// be refreshed, with a retry, or that a refresh is under way.
class StaleNotice extends StatefulWidget {
  /// Creates a [StaleNotice].
  const StaleNotice({
    required this.staleness,
    required this.onRetry,
    super.key,
  });

  /// How old the data is and why.
  final Staleness staleness;

  /// Loads again.
  final VoidCallback onRetry;

  @override
  State<StaleNotice> createState() => _StaleNoticeState();
}

class _StaleNoticeState extends State<StaleNotice> {
  late final Timer _ageTimer;

  @override
  void initState() {
    super.initState();
    // Keeps the shown age true while the screen stays open.
    _ageTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ageTimer.cancel();
    super.dispose();
  }

  String _age(UiLocalizations l10n) {
    final age = DateTime.now().difference(widget.staleness.fetchedAt);
    if (age.inDays > 0) return l10n.staleDays(age.inDays);
    if (age.inHours > 0) return l10n.staleHours(age.inHours);
    if (age.inMinutes > 0) return l10n.staleMinutes(age.inMinutes);
    return l10n.staleUnderAMinute;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UiLocalizations.of(context);
    final theme = Theme.of(context);
    final failure = widget.staleness.failure;
    return LayoutBuilder(
      builder: (context, constraints) => Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenMargin(constraints.maxWidth),
            vertical: 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.history, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_age(l10n), style: theme.textTheme.titleSmall),
                    if (failure != null) ...[
                      const SizedBox(height: 4),
                      // Only this is announced: the age changes every minute.
                      Semantics(
                        liveRegion: true,
                        child: Text(failureMessage(context, failure)),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: widget.onRetry,
                          child: Text(l10n.retry),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(semanticsLabel: l10n.loading),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
