import 'external_ids.dart';
import 'item_ref.dart';
import 'json_object.dart';
import 'media_image.dart';
import 'media_kind.dart';

/// A search result that can be added.
final class AddCandidate {
  /// Creates an [AddCandidate].
  const AddCandidate({
    required this.kind,
    required this.title,
    required this.externalIds,
    this.year,
    this.parentTitle,
    this.overview,
    this.images = const [],
    this.existingRefs = const [],
    this.sourceByInstance = const {},
  });

  /// What would be added.
  final MediaKind kind;

  /// The title found.
  final String title;

  /// The artist of an album or the author of a book.
  final String? parentTitle;

  /// Identifiers to match it across services.
  final ExternalIds externalIds;

  /// Year of first release.
  final int? year;

  /// Short description.
  final String? overview;

  /// Artwork.
  final List<MediaImage> images;

  /// One per instance that already has it.
  final List<ItemRef> existingRefs;

  /// The lookup result of each instance, by instance id, posted back when adding.
  final Map<String, JsonObject> sourceByInstance;
}
