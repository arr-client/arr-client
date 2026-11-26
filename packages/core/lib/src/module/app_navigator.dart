import '../models/add_candidate.dart';
import '../models/item_ref.dart';
import '../models/media_target.dart';

/// Shared flows a module screen can ask for. Implemented by the app; each
/// future completes when the flow is closed.
abstract interface class AppNavigator {
  Future<void> openReleases(MediaTarget target);

  Future<void> openEdit(ItemRef ref);

  Future<void> openDelete(ItemRef ref);

  Future<void> openHistory(ItemRef ref);

  Future<void> openAdd(AddCandidate candidate);
}
