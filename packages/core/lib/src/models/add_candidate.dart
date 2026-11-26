import 'external_ids.dart';
import 'item_ref.dart';
import 'json_object.dart';
import 'media_image.dart';
import 'media_kind.dart';

/// A search result that can be added.
final class AddCandidate {
  const AddCandidate({
    required this.kind,
    required this.title,
    required this.externalIds,
    this.year,
    this.overview,
    this.images = const [],
    this.existingRefs = const [],
    this.sourceByInstance = const {},
  });

  final MediaKind kind;

  final String title;

  final ExternalIds externalIds;

  final int? year;

  final String? overview;

  final List<MediaImage> images;

  /// One per instance that already has it.
  final List<ItemRef> existingRefs;

  /// The lookup result of each instance, by instance id, posted back when adding.
  final Map<String, JsonObject> sourceByInstance;
}
