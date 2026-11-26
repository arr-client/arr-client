import 'item_ref.dart';

/// What an action applies to: an item, or one season of a series.
final class MediaTarget {
  const MediaTarget(this.item, {this.seasonNumber});

  final ItemRef item;

  /// Set only when [item] is a series and one of its seasons is meant.
  final int? seasonNumber;

  @override
  bool operator ==(Object other) =>
      other is MediaTarget &&
      other.item == item &&
      other.seasonNumber == seasonNumber;

  @override
  int get hashCode => Object.hash(item, seasonNumber);
}
