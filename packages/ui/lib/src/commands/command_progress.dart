import 'package:core/core.dart';

/// Where a server task the user started is.
final class CommandProgress {
  /// Creates a [CommandProgress].
  const CommandProgress({this.command, this.lost = false, this.failure});

  /// The task as the server last described it. Null while it is being sent.
  final Command? command;

  /// Whether the task is no longer followed, as it could not be read.
  final bool lost;

  /// Why, where [lost].
  final ServiceFailure? failure;

  /// Whether the task cannot be started again yet.
  bool get busy => !lost && !(command?.isFinished ?? false);
}
