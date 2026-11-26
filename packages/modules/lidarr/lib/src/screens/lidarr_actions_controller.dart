import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:ui/ui.dart';

import 'lidarr_controllers.dart';
import 'lidarr_sources.dart';

/// An artist or album of one instance.
typedef TargetKey = (LidarrSources, MediaTarget);

/// The changes under way on one screen.
final class LidarrActionsState {
  /// Creates a [LidarrActionsState].
  const LidarrActionsState({
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

  /// Whether a file is being deleted, or the tracks read again after it.
  final bool deletingFile;

  LidarrActionsState _monitoring(bool? monitored, {bool saving = false}) =>
      LidarrActionsState(
        monitored: monitored,
        savingMonitored: saving,
        commands: commands,
        deletingFile: deletingFile,
      );

  LidarrActionsState _following(Map<CommandAction, CommandProgress> commands) =>
      LidarrActionsState(
        monitored: monitored,
        savingMonitored: savingMonitored,
        commands: commands,
        deletingFile: deletingFile,
      );

  LidarrActionsState _deleting(bool deletingFile) => LidarrActionsState(
    monitored: monitored,
    savingMonitored: savingMonitored,
    commands: commands,
    deletingFile: deletingFile,
  );
}

/// The changes of one screen, for as long as it is shown.
final lidarrActionsProvider = NotifierProvider.autoDispose
    .family<LidarrActionsController, LidarrActionsState, TargetKey>(
      LidarrActionsController.new,
    );

/// Sends the user's changes, each once, and follows the tasks they start.
///
/// After a change, what this screen shows is read again, and so is what the
/// screens beneath it show of the same artist: the artist, its list of albums,
/// and single albums and their tracks.
class LidarrActionsController extends Notifier<LidarrActionsState> {
  /// Creates the controller of the target of [key].
  LidarrActionsController(this.key);

  /// Whose, and what.
  final TargetKey key;

  late CommandFollower _tasks;

  // The artist of the target; for an album, once the album has said.
  ItemRef? _artist;

  LidarrSources get _sources => key.$1;
  MediaTarget get _target => key.$2;
  ItemKey get _item => (_sources, _target.item);
  bool get _ofAlbum => _target.item.kind == MediaKind.album;

  @override
  LidarrActionsState build() {
    _tasks = CommandFollower(
      commandStatus: _sources.commands.commandStatus,
      onChanged: (commands) => state = state._following(commands),
      onEnded: () => unawaited(reload()),
    );
    ref.onDispose(_tasks.dispose);
    // What is read from the server replaces what was set here.
    if (_ofAlbum) {
      ref.listen(albumProvider(_item), fireImmediately: true, (_, album) {
        if (album case ViewData(:final value, :final staleness)) {
          _artist = value.parent;
          if (staleness == null) _wasRead();
        }
      });
    } else {
      _artist = _target.item;
      ref.listen(artistProvider(_item), (_, artist) {
        if (artist case ViewData(staleness: null)) _wasRead();
      });
    }
    return const LidarrActionsState();
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
      if (_ofAlbum) ...[
        ref.read(albumProvider(_item).notifier).reload(),
        ref.read(tracksProvider(_item).notifier).reload(),
      ],
    ];
    if (_artist case final artist?) {
      final of = (_sources, artist);
      // From an album's screen, only what a screen beneath it already shows.
      if (!_ofAlbum || _isShown(artistProvider(of))) {
        reads.add(ref.read(artistProvider(of).notifier).reload());
      }
      if (!_ofAlbum || _isShown(albumsProvider(of))) {
        reads.add(ref.read(albumsProvider(of).notifier).reload());
      }
      ref.invalidate(historyProvider(of));
      // A change to an artist reaches the albums that are open.
      if (!_ofAlbum) {
        for (final id in ref.read(openAlbumsProvider(_sources))) {
          final album = (_sources, id);
          // One that has not said its artist yet may be of this one.
          if (ref.read(albumProvider(album)) case ViewData(:final value)
              when value.parent != artist) {
            continue;
          }
          reads.add(ref.read(albumProvider(album).notifier).reload());
          if (_isShown(tracksProvider(album))) {
            reads.add(ref.read(tracksProvider(album).notifier).reload());
          }
          ref.invalidate(historyProvider(album));
        }
      }
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

  /// Deletes [file], which this instance listed. The album is read again where
  /// the file is, or may be, gone.
  ServiceResult<void> deleteFile(MediaFile file) async {
    final alive = ref.keepAlive();
    try {
      state = state._deleting(true);
      final result = await _sources.library.deleteFile(file);
      if (!ref.mounted) return result;
      if (result case Ok() || Err(error: NotFound() || OutcomeUnknown())) {
        // Files stay out of reach until the tracks have been read again.
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
