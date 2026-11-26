import '../../models/media_target.dart';
import '../../models/release.dart';
import '../capability.dart';
import '../service_result.dart';

/// Interactive release search.
abstract interface class ReleaseProvider implements Capability {
  ServiceResult<List<Release>> releases(MediaTarget target);

  ServiceResult<void> grab(Release release);
}
