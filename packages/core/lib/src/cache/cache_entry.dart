import '../models/item_state.dart';
import '../models/media_kind.dart';

/// One cached library item: summary columns and the server's JSON.
final class CacheEntry {
  const CacheEntry({
    required this.instanceId,
    required this.kind,
    required this.remoteId,
    required this.sortTitle,
    required this.state,
    required this.monitored,
    required this.rawJson,
    required this.fetchedAt,
    this.parentRemoteId,
    this.qualityProfileId,
    this.addedAt,
    this.tagIds = const [],
  });

  final String instanceId;

  final MediaKind kind;

  final int remoteId;

  /// The series, artist, album or author an item belongs to.
  final int? parentRemoteId;

  final String sortTitle;

  final ItemState state;

  final bool monitored;

  final int? qualityProfileId;

  final List<int> tagIds;

  final DateTime? addedAt;

  final String rawJson;

  final DateTime fetchedAt;
}
