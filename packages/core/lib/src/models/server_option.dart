import 'server_option_kind.dart';

/// A choice configured on the server, read only.
final class ServerOption {
  const ServerOption({
    required this.kind,
    required this.id,
    required this.label,
    this.freeSpace,
  });

  final ServerOptionKind kind;

  final int id;

  final String label;

  /// Bytes; root folders only.
  final int? freeSpace;
}
