import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// Says which services could not be searched, below the results so that its
/// arrival moves none of them.
class SearchFailures extends StatelessWidget {
  const SearchFailures({
    required this.failures,
    required this.margin,
    required this.onRetry,
    super.key,
  });

  /// The name of each failed service and why it failed.
  final List<(String, ServiceFailure)> failures;

  /// The screen margin.
  final double margin;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: margin, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (name, failure) in failures)
                        _Failure(name: name, failure: failure),
                    ],
                  ),
                ),
              ),
              // Beside the list, so that it stays in view however long that is.
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: UiLocalizations.of(context).retry,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.name, required this.failure});

  final String name;
  final ServiceFailure failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).searchFailed(name),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(failureMessage(context, failure)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
