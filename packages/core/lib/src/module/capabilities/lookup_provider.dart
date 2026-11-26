import '../../models/add_candidate.dart';
import '../../models/add_choices.dart';
import '../../models/add_options.dart';
import '../../models/item_ref.dart';
import '../../models/media_kind.dart';
import '../capability.dart';
import '../service_result.dart';

/// Searching for new items and adding them.
abstract interface class LookupProvider implements Capability {
  /// The kind of the items this adds.
  MediaKind get itemKind;

  ServiceResult<List<AddCandidate>> lookup(String term);

  ServiceResult<AddOptions> addOptions();

  /// Returns the new item. An item that already exists is a `Conflict`.
  ServiceResult<ItemRef> add(AddCandidate candidate, AddChoices choices);
}
