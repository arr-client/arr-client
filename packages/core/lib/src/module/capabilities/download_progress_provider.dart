import '../../models/download_progress.dart';
import '../capability.dart';
import '../service_result.dart';

/// A download client's own figures. Read only by design.
abstract interface class DownloadProgressProvider implements Capability {
  ServiceResult<List<DownloadProgress>> progress();
}
