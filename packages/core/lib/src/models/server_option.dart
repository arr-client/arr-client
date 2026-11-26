import 'server_option_kind.dart';

/// A choice configured on the server, read only.
final class ServerOption {
  /// Creates a [ServerOption].
  const ServerOption({
    required this.kind,
    required this.id,
    required this.label,
    this.freeSpace,
  });

  /// What the option is.
  final ServerOptionKind kind;

  /// The server's id of the option.
  final int id;

  /// Name or path to show.
  final String label;

  /// Bytes; root folders only.
  final int? freeSpace;
}
