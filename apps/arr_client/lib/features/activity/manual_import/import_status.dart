import 'dart:async';

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'manual_import_controller.dart';

/// What there is to say above the files: how a sent import stands, and what
/// could not be loaded.
class ImportStatus extends StatelessWidget {
  const ImportStatus({
    required this.instanceName,
    required this.state,
    required this.controller,
    super.key,
  });

  final String instanceName;
  final ManualImportState state;
  final ManualImportController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Widget notice(
      List<String> lines, {
      String? action,
      VoidCallback? onAction,
      bool running = false,
    }) => Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(liveRegion: true, child: Text(lines.join('\n'))),
            if (running) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(semanticsLabel: lines.first),
            ],
            if (action != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: onAction, child: Text(action)),
              ),
          ],
        ),
      ),
    );

    Widget loadFailure(String what, ServiceFailure failure) => notice(
      [what, failureMessage(context, failure)],
      action: strings.manualImportRetry,
      onAction: () => unawaited(controller.retry()),
    );

    final command = state.command;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.outcomeUnknown)
          notice([strings.manualImportSendUnknown(instanceName)]),
        if (command != null)
          switch (command.outcome) {
            CommandOutcome.pending => switch (state.commandFailure) {
              null => notice([
                strings.manualImportRunning(instanceName),
              ], running: true),
              final failure => notice(
                [
                  strings.manualImportRunning(instanceName),
                  strings.manualImportProgressFailed,
                  failureMessage(context, failure),
                ],
                action: strings.manualImportCheckAgain,
                onAction: () => unawaited(controller.checkCommand()),
              ),
            },
            CommandOutcome.succeeded => notice([
              strings.manualImportSucceeded(instanceName),
            ]),
            CommandOutcome.failed => notice([
              strings.manualImportFailed(instanceName),
              ?command.message,
            ]),
            CommandOutcome.unknown => notice([
              strings.manualImportOutcomeUnknown(instanceName),
            ]),
          },
        // Not while the whole read has failed: the stale notice says why.
        if (!state.isStale) ...[
          if (state.itemsFailure case final failure?)
            loadFailure(strings.manualImportItemsFailed, failure),
          if (state.choicesFailure case final failure?)
            loadFailure(strings.manualImportChoicesFailed, failure),
          if (state.episodeFailures.values.firstOrNull case final failure?)
            loadFailure(strings.manualImportEpisodesFailed, failure),
        ],
      ],
    );
  }
}
