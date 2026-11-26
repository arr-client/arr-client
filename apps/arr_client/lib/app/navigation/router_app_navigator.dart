import 'package:core/core.dart';
import 'package:go_router/go_router.dart';

import 'locations.dart';

/// The [AppNavigator] of the running app. The flows are not built yet: each
/// opens a page that says so, and its future completes when that is closed.
final class RouterAppNavigator implements AppNavigator {
  /// Set by the root widget while it is shown. Without it nothing opens.
  GoRouter? router;

  @override
  Future<void> openReleases(MediaTarget target) =>
      _flow(target.item, InstanceFlow.releases);

  @override
  Future<void> openEdit(ItemRef ref) => _flow(ref, InstanceFlow.edit);

  @override
  Future<void> openDelete(ItemRef ref) => _flow(ref, InstanceFlow.delete);

  @override
  Future<void> openHistory(ItemRef ref) => _flow(ref, InstanceFlow.history);

  @override
  Future<void> openAdd(AddCandidate candidate) => _push(addLocation);

  Future<void> _flow(ItemRef ref, InstanceFlow flow) =>
      _push(instanceFlowLocation(ref.instanceId, flow));

  Future<void> _push(String location) async {
    await router?.push<void>(location);
  }
}
