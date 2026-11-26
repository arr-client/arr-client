import '../../models/media_target.dart';
import '../../models/release.dart';
import '../capability.dart';
import '../service_result.dart';

/// Interactive release search.
abstract interface class ReleaseProvider implements Capability {
  /// Searches the indexers for [target].
  ServiceResult<List<Release>> releases(MediaTarget target);

  /// Downloads [release].
  ServiceResult<void> grab(Release release);
}
