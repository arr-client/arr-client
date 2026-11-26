import 'package:core/core.dart';
import 'package:go_router/go_router.dart';

import '../../features/search/add_request.dart';
import 'locations.dart';

/// The [AppNavigator] of the running app. A flow's future completes when its
/// page is closed. Those not built yet open a page that says so.
final class RouterAppNavigator implements AppNavigator {
  /// Set by the root widget while it is shown. Without it nothing opens.
  GoRouter? router;

  @override
  Future<void> openReleases(MediaTarget target) =>
      _push(releasesLocation(target));

  @override
  Future<void> openEdit(ItemRef ref) => _flow(ref, InstanceFlow.edit);

  @override
  Future<void> openDelete(ItemRef ref) => _flow(ref, InstanceFlow.delete);

  @override
  Future<void> openHistory(ItemRef ref) => _push(itemHistoryLocation(ref));

  @override
  Future<void> openAdd(AddCandidate candidate) =>
      _push(addLocation, extra: AddRequest(candidate));

  Future<void> _flow(ItemRef ref, InstanceFlow flow) =>
      _push(instanceFlowLocation(ref.instanceId, flow));

  Future<void> _push(String location, {Object? extra}) async {
    await router?.push<void>(location, extra: extra);
  }
}
