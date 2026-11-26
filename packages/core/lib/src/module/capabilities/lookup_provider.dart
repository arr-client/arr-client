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

  /// The choices for adding an item of one of [itemKinds].
  ServiceResult<AddOptions> addOptions(MediaKind kind);

  /// Returns the new item. An item that already exists is a `Conflict`.
  ServiceResult<ItemRef> add(AddCandidate candidate, AddChoices choices);
}
