import '../models/item_state.dart';
import '../models/media_kind.dart';

/// One cached library item: summary columns and the server's JSON.
final class CacheEntry {
  /// Creates a [CacheEntry].
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

  /// The instance the item belongs to.
  final String instanceId;

  /// What the item is.
  final MediaKind kind;

  /// The server's id of the item.
  final int remoteId;

  /// The series, artist, album or author an item belongs to.
  final int? parentRemoteId;

  /// The title to sort by.
  final String sortTitle;

  /// The item's state, for filtering.
  final ItemState state;

  /// Whether the server monitors the item.
  final bool monitored;

  /// The item's quality profile, for filtering.
  final int? qualityProfileId;

  /// The item's tags, for filtering.
  final List<int> tagIds;

  /// When the server added the item.
  final DateTime? addedAt;

  /// The server's record, as received.
  final String rawJson;

  /// When the item was last fetched.
  final DateTime fetchedAt;
}
