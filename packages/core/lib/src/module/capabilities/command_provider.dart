import '../../models/command.dart';
import '../../models/command_action.dart';
import '../../models/media_target.dart';
import '../capability.dart';
import '../service_result.dart';

/// Server tasks the user can start. Each returns the accepted command.
abstract interface class CommandProvider implements Capability {
  /// Whether the server offers [action] at the level of [target].
  bool supports(CommandAction action, MediaTarget target);

  /// Searches for releases of [targets].
  ServiceResult<Command> search(List<MediaTarget> targets);

  /// Refreshes the metadata of [target].
  ServiceResult<Command> refresh(MediaTarget target);

  /// Rescans the files of [target].
  ServiceResult<Command> rescan(MediaTarget target);

  /// The current state of a command.
  ServiceResult<Command> commandStatus(int commandId);
}
