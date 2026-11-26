import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'command_progress.dart';

/// Starts server tasks, each once, and reads how they are doing until they end.
///
/// One serves the tasks of one thing, one per [CommandAction] at a time. A
/// screen's controller owns it and must [dispose] of it, which stops the reads.
final class CommandFollower {
  /// Creates a [CommandFollower].
  CommandFollower({
    required this.commandStatus,
    required this.onChanged,
    required this.onEnded,
  });

  /// Reads a task, as `CommandProvider.commandStatus` does.
  final ServiceResult<Command> Function(int commandId) commandStatus;

  /// Called with all tasks whenever one changes.
  final void Function(Map<CommandAction, CommandProgress> commands) onChanged;

  /// Called when a task has ended or is given up on: it may have changed what
  /// the screen shows.
  final VoidCallback onEnded;

  /// How long between two reads of a running task.
  static const pollEvery = Duration(seconds: 3);

  // How many reads in a row may fail before a task is given up on.
  static const _attempts = 3;

  /// Whether what started the tasks is on screen. While it is not, nothing is
  /// read; the reads go on once it is again.
  bool shown = true;

  final _timers = <CommandAction, Timer>{};
  var _commands = const <CommandAction, CommandProgress>{};
  var _disposed = false;

  /// Sends the task [action] by calling [send] once, and follows it if the
  /// server accepts it. The caller says how the sending went.
  ServiceResult<Command> start(
    CommandAction action,
    ServiceResult<Command> Function() send,
  ) async {
    _timers.remove(action)?.cancel();
    _set(action, const CommandProgress());
    final result = await send();
    if (_disposed) return result;
    switch (result) {
      case Ok(:final value):
        _follow(action, value);
      case Err():
        _set(action, null);
    }
    return result;
  }

  /// Stops following.
  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _set(CommandAction action, CommandProgress? progress) {
    _commands = Map.unmodifiable({
      for (final MapEntry(:key, :value) in _commands.entries)
        if (key != action) key: value,
      action: ?progress,
    });
    onChanged(_commands);
  }

  void _follow(CommandAction action, Command command) {
    _set(action, CommandProgress(command: command));
    if (command.isFinished) {
      onEnded();
    } else {
      _schedule(action, command, 0);
    }
  }

  void _schedule(CommandAction action, Command command, int failures) {
    _timers[action] = Timer(
      pollEvery,
      () => unawaited(_poll(action, command, failures)),
    );
  }

  Future<void> _poll(
    CommandAction action,
    Command command,
    int failures,
  ) async {
    // Nothing is asked while the screen or the app is out of sight.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!shown || lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _schedule(action, command, failures);
      return;
    }
    final result = await commandStatus(command.id);
    if (_disposed) return;
    switch (result) {
      case Ok(:final value):
        _follow(action, value);
      case Err(:final error)
          when error is! NotFound && failures + 1 < _attempts:
        _schedule(action, command, failures + 1);
      case Err(:final error):
        _set(
          action,
          CommandProgress(command: command, lost: true, failure: error),
        );
        onEnded();
    }
  }
}
