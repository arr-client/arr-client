import 'command_outcome.dart';
import 'command_result.dart';
import 'command_status.dart';

/// A task the server is running or has run.
final class Command {
  /// Creates a [Command].
  const Command({
    required this.id,
    required this.name,
    required this.status,
    this.result,
    this.message,
  });

  /// The server's id of the command.
  final int id;

  /// The server's name for the task.
  final String name;

  /// Where the task is.
  final CommandStatus status;

  /// How it ended, where the server says.
  final CommandResult? result;

  /// The server's message.
  final String? message;

  /// What can be said about the task: [status] decides, and [result] only
  /// counts once it is [CommandStatus.completed].
  CommandOutcome get outcome => switch (status) {
    CommandStatus.queued || CommandStatus.started => CommandOutcome.pending,
    CommandStatus.completed => switch (result) {
      null || CommandResult.successful => CommandOutcome.succeeded,
      CommandResult.unsuccessful => CommandOutcome.failed,
      CommandResult.indeterminate ||
      CommandResult.unknown => CommandOutcome.unknown,
    },
    CommandStatus.failed ||
    CommandStatus.aborted ||
    CommandStatus.cancelled ||
    CommandStatus.orphaned => CommandOutcome.failed,
    CommandStatus.unknown => CommandOutcome.unknown,
  };

  /// Whether to stop polling the command.
  bool get isFinished => outcome != CommandOutcome.pending;
}
