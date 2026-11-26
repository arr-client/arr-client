import 'command_result.dart';
import 'command_status.dart';

/// A task the server is running or has run.
final class Command {
  const Command({
    required this.id,
    required this.name,
    required this.status,
    this.result,
    this.message,
  });

  final int id;

  final String name;

  final CommandStatus status;

  final CommandResult? result;

  final String? message;
}
