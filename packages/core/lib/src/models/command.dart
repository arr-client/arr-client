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
}
