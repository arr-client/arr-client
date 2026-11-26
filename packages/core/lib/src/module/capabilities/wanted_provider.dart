import '../../models/library_item.dart';
import '../../models/result_page.dart';
import '../capability.dart';
import '../service_result.dart';

/// Items the server is still looking for. Pages start at 1.
abstract interface class WantedProvider implements Capability {
  ServiceResult<ResultPage<LibraryItem>> missing({int page = 1});

  ServiceResult<ResultPage<LibraryItem>> cutoffUnmet({int page = 1});
}
