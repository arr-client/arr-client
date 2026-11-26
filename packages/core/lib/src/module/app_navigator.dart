import '../models/add_candidate.dart';
import '../models/item_ref.dart';
import '../models/media_target.dart';

/// Shared flows a module screen can ask for. Implemented by the app; each
/// future completes when the flow is closed.
abstract interface class AppNavigator {
  /// Opens interactive release search.
  Future<void> openReleases(MediaTarget target);

  /// Opens the edit sheet.
  Future<void> openEdit(ItemRef ref);

  /// Opens the delete confirmation.
  Future<void> openDelete(ItemRef ref);

  /// Opens the item's history.
  Future<void> openHistory(ItemRef ref);

  /// Opens the add flow for a search result.
  Future<void> openAdd(AddCandidate candidate);
}
