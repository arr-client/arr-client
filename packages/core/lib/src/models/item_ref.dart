import 'media_kind.dart';

/// The global key of a server item.
final class ItemRef {
  const ItemRef({
    required this.instanceId,
    required this.kind,
    required this.remoteId,
  });

  final String instanceId;
  final MediaKind kind;
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
