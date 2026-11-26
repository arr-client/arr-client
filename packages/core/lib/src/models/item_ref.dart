import 'media_kind.dart';

/// The global key of a server item.
final class ItemRef {
  /// Creates an [ItemRef].
  const ItemRef({
    required this.instanceId,
    required this.kind,
    required this.remoteId,
  });

  /// The instance that holds the item.
  final String instanceId;

  /// What the item is.
  final MediaKind kind;

  /// The server's id of the item.
  final int remoteId;

  @override
  bool operator ==(Object other) =>
      other is ItemRef &&
      other.instanceId == instanceId &&
      other.kind == kind &&
      other.remoteId == remoteId;

  @override
  int get hashCode => Object.hash(instanceId, kind, remoteId);
}
