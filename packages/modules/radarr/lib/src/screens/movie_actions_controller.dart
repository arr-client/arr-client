import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'movie_detail_controller.dart';

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

  MovieActionsState _following(Map<CommandAction, CommandProgress> commands) =>
      MovieActionsState(
        monitored: monitored,
        savingMonitored: savingMonitored,
        commands: commands,
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

  late CommandFollower _tasks;

  @override
  MovieActionsState build() {
    _tasks = CommandFollower(
      commandStatus: source.commands.commandStatus,
      onChanged: (commands) => state = state._following(commands),
      onEnded: () => unawaited(reload()),
    );
    ref.onDispose(_tasks.dispose);
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

  /// Whether the screen is shown; tasks are not read while it is covered.
  set shown(bool shown) => _tasks.shown = shown;

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
  ServiceResult<Command> start(CommandAction action) {
    final target = MediaTarget(source.item);
    return _tasks.start(
      action,
      () => switch (action) {
        CommandAction.search => source.commands.search([target]),
        CommandAction.refresh => source.commands.refresh(target),
        CommandAction.rescan => source.commands.rescan(target),
      },
    );
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
