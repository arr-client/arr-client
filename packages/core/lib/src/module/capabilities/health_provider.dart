import '../../models/disk_space.dart';
import '../../models/health_issue.dart';
import '../capability.dart';
import '../service_result.dart';

/// Server health, read only.
abstract interface class HealthProvider implements Capability {
  /// False where the service reports health only.
  bool get providesDiskSpace;

  /// Problems the server reports.
  ServiceResult<List<HealthIssue>> health();

  /// Empty when [providesDiskSpace] is false.
  ServiceResult<List<DiskSpace>> diskSpace();
}
