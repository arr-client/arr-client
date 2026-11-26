import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:ui/ui.dart';

import 'sonarr_controllers.dart';
import 'sonarr_sources.dart';

/// A series, one of its seasons or an episode, of one instance.
typedef TargetKey = (SonarrSources, MediaTarget);

/// The changes under way on one screen.
final class SonarrActionsState {
  /// Creates a [SonarrActionsState].
  const SonarrActionsState({
    this.monitored,
    this.savingMonitored = false,
    this.commands = const {},
    this.deletingFile = false,
  });

  /// What monitoring was set to, until the server has been read again. Null
  /// where what was read says.
  final bool? monitored;

  /// Whether a change of monitoring awaits the server's answer.
  final bool savingMonitored;

  /// The tasks started from this screen.
  final Map<CommandAction, CommandProgress> commands;

  /// Whether a file is being deleted, or the episode read again after it.
  final bool deletingFile;

  SonarrActionsState _monitoring(bool? monitored, {bool saving = false}) =>
      SonarrActionsState(
        monitored: monitored,
        savingMonitored: saving,
        commands: commands,
        deletingFile: deletingFile,
      );

  SonarrActionsState _following(Map<CommandAction, CommandProgress> commands) =>
      SonarrActionsState(
        monitored: monitored,
        savingMonitored: savingMonitored,
        commands: commands,
        deletingFile: deletingFile,
      );

  SonarrActionsState _deleting(bool deletingFile) => SonarrActionsState(
    monitored: monitored,
    savingMonitored: savingMonitored,
    commands: commands,
    deletingFile: deletingFile,
  );
}

/// The changes of one screen, for as long as it is shown.
final sonarrActionsProvider = NotifierProvider.autoDispose
    .family<SonarrActionsController, SonarrActionsState, TargetKey>(
      SonarrActionsController.new,
    );

/// Sends the user's changes, each once, and follows the tasks they start.
///
/// After a change, what this screen shows is read again, and so is what the
/// screens beneath it show of the same series.
class SonarrActionsController extends Notifier<SonarrActionsState> {
  /// Creates the controller of the target of [key].
  SonarrActionsController(this.key);

  /// Whose, and what.
  final TargetKey key;

  late CommandFollower _tasks;

  // The series of the target; for an episode, once the episode has said.
  ItemRef? _series;

  SonarrSources get _sources => key.$1;
  MediaTarget get _target => key.$2;
  ItemKey get _item => (_sources, _target.item);
  bool get _ofEpisode => _target.item.kind == MediaKind.episode;

  @override
  SonarrActionsState build() {
    _tasks = CommandFollower(
      commandStatus: _sources.commands.commandStatus,
      onChanged: (commands) => state = state._following(commands),
      onEnded: () => unawaited(reload()),
    );
    ref.onDispose(_tasks.dispose);
    // What is read from the server replaces what was set here.
    if (_ofEpisode) {
      ref.listen(episodeProvider(_item), fireImmediately: true, (_, episode) {
        if (episode case ViewData(:final value, :final staleness)) {
          _series = value.parent;
          if (staleness == null) _wasRead();
        }
      });
    } else {
      _series = _target.item;
      ref.listen(seriesProvider(_item), (_, series) {
        if (series case ViewData(staleness: null)) _wasRead();
      });
    }
    return const SonarrActionsState();
  }

  void _wasRead() {
    // There is no state yet while build runs, and nothing to replace.
    final now = stateOrNull;
    if (now != null && !now.savingMonitored && now.monitored != null) {
      state = now._monitoring(null);
    }
  }

  /// Whether the screen is shown; tasks are not read while it is covered.
  set shown(bool shown) => _tasks.shown = shown;

  // The replacement the deprecation names, `provider.exist`, is not in
  // Riverpod 3.5.0.
  // ignore: deprecated_member_use
  bool _isShown(ProviderBase<Object?> provider) => ref.exists(provider);

  /// Reads from the server again.
  Future<void> reload() async {
    if (!ref.mounted) return;
    ref.invalidate(historyProvider(_item));
    final reads = <Future<void>>[
      if (_ofEpisode) ref.read(episodeProvider(_item).notifier).reload(),
    ];
    if (_series case final series?) {
      final of = (_sources, series);
      // From an episode's screen, only what a screen beneath it already shows.
      if (!_ofEpisode || _isShown(seriesProvider(of))) {
        reads.add(ref.read(seriesProvider(of).notifier).reload());
      }
      if (!_ofEpisode || _isShown(episodesProvider(of))) {
        reads.add(ref.read(episodesProvider(of).notifier).reload());
      }
      ref.invalidate(historyProvider(of));
    }
    await Future.wait(reads);
  }

  /// Turns monitoring on or off. The new value shows at once and is taken back
  /// if the server does not accept it.
  ServiceResult<void> setMonitored(bool monitored) async {
    // Kept until the server has answered, also if the screen is left, so that
    // the screens beneath it are read again.
    final alive = ref.keepAlive();
    try {
      state = state._monitoring(monitored, saving: true);
      final result = await _sources.library.setMonitored(_target, monitored);
      if (!ref.mounted) return result;
      state = state._monitoring(result is Ok ? monitored : null);
      if (result is Ok) unawaited(reload());
      return result;
    } finally {
      alive.close();
    }
  }

  /// Starts the task [action] and follows it.
  ServiceResult<Command> start(CommandAction action) => _tasks.start(
    action,
    () => switch (action) {
      CommandAction.search => _sources.commands.search([_target]),
      CommandAction.refresh => _sources.commands.refresh(_target),
      CommandAction.rescan => _sources.commands.rescan(_target),
    },
  );

  /// Deletes [file], which this instance listed. The episode is read again
  /// where the file is, or may be, gone.
  ServiceResult<void> deleteFile(MediaFile file) async {
    final alive = ref.keepAlive();
    try {
      state = state._deleting(true);
      final result = await _sources.library.deleteFile(file);
      if (!ref.mounted) return result;
      if (result case Ok() || Err(error: NotFound() || OutcomeUnknown())) {
        // The file stays out of reach until the episode has been read again.
        unawaited(
          reload().whenComplete(() {
            if (ref.mounted) state = state._deleting(false);
          }),
        );
      } else {
        state = state._deleting(false);
      }
      return result;
    } finally {
      alive.close();
    }
  }
}
