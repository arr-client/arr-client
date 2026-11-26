import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../commands/command_progress.dart';
import '../l10n/generated/ui_localizations.dart';
import 'failure_message.dart';

/// What to say once the server has accepted the task [action].
String commandAcceptedMessage(UiLocalizations strings, CommandAction action) =>
    switch (action) {
      CommandAction.search => strings.searchStarted,
      CommandAction.refresh => strings.refreshStarted,
      CommandAction.rescan => strings.rescanStarted,
    };

/// How one server task is doing, with the server's message or the reason it can
/// no longer be read. Changes are announced to screen readers.
class CommandProgressView extends StatelessWidget {
  /// Creates a [CommandProgressView].
  const CommandProgressView({
    required this.action,
    required this.progress,
    super.key,
  });

  /// Which task.
  final CommandAction action;

  /// Where it is.
  final CommandProgress progress;

  @override
  Widget build(BuildContext context) {
    final strings = UiLocalizations.of(context);
    final task = switch (action) {
      CommandAction.search => strings.taskSearch,
      CommandAction.refresh => strings.taskRefresh,
      CommandAction.rescan => strings.taskRescan,
    };
    final command = progress.command;
    final text = progress.lost
        ? strings.taskLost(task)
        : switch (command?.outcome) {
            null => strings.taskSending(task),
            CommandOutcome.pending
                when command?.status == CommandStatus.queued =>
              strings.taskQueued(task),
            CommandOutcome.pending => strings.taskRunning(task),
            CommandOutcome.succeeded => strings.taskSucceeded(task),
            CommandOutcome.failed => strings.taskFailed(task),
            CommandOutcome.unknown => strings.taskUnknown(task),
          };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (progress.failure case final failure?)
            Text(failureMessage(context, failure))
          else if (command?.message case final message?)
            Text(message),
          if (progress.busy) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(semanticsLabel: text),
          ],
        ],
      ),
    );
  }
}
