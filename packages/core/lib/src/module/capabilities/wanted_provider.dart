import '../../models/library_item.dart';
import '../../models/result_page.dart';
import '../capability.dart';
import '../service_result.dart';

/// Items the server is still looking for. Pages start at 1.
abstract interface class WantedProvider implements Capability {
  /// Monitored items without a file.
  ServiceResult<ResultPage<LibraryItem>> missing({int page = 1});

  /// Items below their quality cutoff.
  ServiceResult<ResultPage<LibraryItem>> cutoffUnmet({int page = 1});
}
