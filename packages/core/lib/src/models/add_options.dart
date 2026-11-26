import 'monitor_option.dart';
import 'server_option.dart';

/// What can be chosen when adding to one instance.
final class AddOptions {
  const AddOptions({required this.serverOptions, required this.monitorOptions});

  final List<ServerOption> serverOptions;

  final List<MonitorOption> monitorOptions;
}
