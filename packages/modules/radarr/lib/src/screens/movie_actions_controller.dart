import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'movie_detail_controller.dart';

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

/// The changes under way on one movie screen.
final class MovieActionsState {
  /// Creates a [MovieActionsState].
  const MovieActionsState({
    this.monitored,
    this.savingMonitored = false,
    this.commands = const {},
    this.deletingFile = false,
  });

  /// What monitoring was set to, until the movie has been read again. Null
  /// where the movie says.
  final bool? monitored;

  /// Whether a change of monitoring awaits the server's answer.
  final bool savingMonitored;

  /// The tasks started from this screen.
  final Map<CommandAction, CommandProgress> commands;

  /// Whether a file is being deleted, or the files read again after it.
  final bool deletingFile;

  MovieActionsState _monitoring(bool? monitored, {bool saving = false}) =>
      MovieActionsState(
        monitored: monitored,
        savingMonitored: saving,
        commands: commands,
        deletingFile: deletingFile,
      );

  MovieActionsState _command(CommandAction action, CommandProgress? progress) =>
      MovieActionsState(
        monitored: monitored,
        savingMonitored: savingMonitored,
        commands: {
          for (final MapEntry(:key, :value) in commands.entries)
            if (key != action) key: value,
          action: ?progress,
        },
        deletingFile: deletingFile,
      );

  MovieActionsState _deleting(bool deletingFile) => MovieActionsState(
    monitored: monitored,
    savingMonitored: savingMonitored,
    commands: commands,
    deletingFile: deletingFile,
  );
}

/// The changes of one movie screen, for as long as it is shown.
final movieActionsProvider = NotifierProvider.autoDispose
    .family<MovieActionsController, MovieActionsState, MovieDetailSource>(
      MovieActionsController.new,
    );

/// Sends the user's changes, each once, and follows the tasks they start.
class MovieActionsController extends Notifier<MovieActionsState> {
  /// Creates the controller of the movie of [source].
  MovieActionsController(this.source);

  /// Whose movie, and where changes go.
  final MovieDetailSource source;

  /// How long between two reads of a running task.
  static const pollEvery = Duration(seconds: 3);

  // How many reads in a row may fail before a task is given up on.
  static const _attempts = 3;

  final _timers = <CommandAction, Timer>{};

  @override
  MovieActionsState build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    // A movie read from the server replaces what was set here.
    ref.listen(movieDetailProvider(source).select((state) => state.movie), (
      _,
      movie,
    ) {
      if (movie case ViewData(staleness: null)
          when !state.savingMonitored && state.monitored != null) {
        state = state._monitoring(null);
      }
    });
    return const MovieActionsState();
  }

  /// Reads the movie from the server again.
  Future<void> reload() async {
    if (!ref.mounted) return;
    await ref.read(movieDetailProvider(source).notifier).refresh();
  }

  /// Turns monitoring on or off. The new value shows at once and is taken back
  /// if the server does not accept it.
  ServiceResult<void> setMonitored(bool monitored) async {
    state = state._monitoring(monitored, saving: true);
    final result = await source.library.setMonitored(
      MediaTarget(source.item),
      monitored,
    );
    if (!ref.mounted) return result;
    state = state._monitoring(result is Ok ? monitored : null);
    if (result is Ok) unawaited(reload());
    return result;
  }

  /// Starts the task [action] and follows it.
  ServiceResult<Command> start(CommandAction action) async {
    _timers.remove(action)?.cancel();
    state = state._command(action, const CommandProgress());
    final target = MediaTarget(source.item);
    final result = await switch (action) {
      CommandAction.search => source.commands.search([target]),
      CommandAction.refresh => source.commands.refresh(target),
      CommandAction.rescan => source.commands.rescan(target),
    };
    if (!ref.mounted) return result;
    switch (result) {
      case Ok(:final value):
        _follow(action, value);
      case Err():
        state = state._command(action, null);
    }
    return result;
  }

  void _follow(CommandAction action, Command command) {
    state = state._command(action, CommandProgress(command: command));
    if (command.isFinished) {
      // The task may have changed what the screen shows.
      unawaited(reload());
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
    // Nothing is asked while the app is out of sight.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _schedule(action, command, failures);
      return;
    }
    final result = await source.commands.commandStatus(command.id);
    if (!ref.mounted) return;
    switch (result) {
      case Ok(:final value):
        _follow(action, value);
      case Err(:final error)
          when error is! NotFound && failures + 1 < _attempts:
        _schedule(action, command, failures + 1);
      case Err(:final error):
        state = state._command(
          action,
          CommandProgress(command: command, lost: true, failure: error),
        );
        unawaited(reload());
    }
  }

  /// Deletes [file], which this instance listed. The movie is read again where
  /// the file is, or may be, gone.
  ServiceResult<void> deleteFile(MediaFile file) async {
    state = state._deleting(true);
    final result = await source.library.deleteFile(file);
    if (!ref.mounted) return result;
    if (result case Ok() || Err(error: NotFound() || OutcomeUnknown())) {
      // The file stays out of reach until the list has been read again.
      unawaited(
        reload().whenComplete(() {
          if (ref.mounted) state = state._deleting(false);
        }),
      );
    } else {
      state = state._deleting(false);
    }
    return result;
  }
}
