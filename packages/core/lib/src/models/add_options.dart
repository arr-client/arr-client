import 'monitor_option.dart';
import 'server_option.dart';

/// What can be chosen when adding to one instance.
final class AddOptions {
  /// Creates an [AddOptions].
  const AddOptions({required this.serverOptions, required this.monitorOptions});

  /// Root folders, profiles and tags of the instance.
  final List<ServerOption> serverOptions;

  /// What can be monitored.
  final List<MonitorOption> monitorOptions;
}
