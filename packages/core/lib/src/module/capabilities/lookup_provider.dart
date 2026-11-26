import '../../models/add_candidate.dart';
import '../../models/add_choices.dart';
import '../../models/add_options.dart';
import '../../models/item_ref.dart';
import '../../models/media_kind.dart';
import '../capability.dart';
import '../service_result.dart';

/// Searching for new items and adding them.
abstract interface class LookupProvider implements Capability {
  /// The kinds of item this adds, for example artists and albums.
  Set<MediaKind> get itemKinds;

  /// Items matching [term], of every kind in [itemKinds].
  ServiceResult<List<AddCandidate>> lookup(String term);

  /// What this instance answers now for [candidate], found by a shared
  /// identifier, whichever instance or search it came from. Its `existingRefs`
  /// says whether this instance has the item, and its `sourceByInstance` holds
  /// the record that [add] posts. `NotFound` if this instance's search does not
  /// give it, or [candidate] has no identifier it can be looked up by.
  ServiceResult<AddCandidate> find(AddCandidate candidate);

  /// The choices for adding an item of one of [itemKinds].
  ServiceResult<AddOptions> addOptions(MediaKind kind);

  /// Returns the new item. An item that already exists is a `Conflict`.
  ServiceResult<ItemRef> add(AddCandidate candidate, AddChoices choices);
}
