import '../../models/download_progress.dart';
import '../capability.dart';
import '../service_result.dart';

/// A download client's own figures. Read only by design.
abstract interface class DownloadProgressProvider implements Capability {
  /// Every torrent the client has.
  ServiceResult<List<DownloadProgress>> progress();
}
