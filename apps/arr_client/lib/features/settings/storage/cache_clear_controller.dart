import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../library/library_controller.dart';

/// Whether the cached data is being removed. It stays when Settings is left, so
/// that a second removal cannot start beside the first.
final cacheClearProvider = NotifierProvider<CacheClearController, bool>(
  CacheClearController.new,
);

/// Removes what was saved of the servers' libraries and artwork, of every
/// profile. Services, credentials and preferences are not touched.
class CacheClearController extends Notifier<bool> {
  @override
  bool build() => false;

  /// False if something could not be removed.
  Future<bool> clear() async {
    final services = ref.read(appServicesProvider);
    state = true;
    var complete = true;
    // Each is tried, whatever becomes of the other.
    for (final (what, remove) in [
      ('library data', services.cache.clear),
      ('artwork', services.artwork.clear),
    ]) {
      try {
        await remove();
      } catch (error) {
        // The type only: the text of an error may quote an address.
        services.log.log(
          LogLevel.warning,
          'The cached $what could not be removed (${error.runtimeType})',
        );
        complete = false;
      }
    }
    // The libraries hold their items for as long as the app runs, and must not
    // go on showing what was removed. They ask the servers when next shown.
    ref.invalidate(libraryProvider);
    state = false;
    return complete;
  }
}
