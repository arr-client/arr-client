import '../../models/blocklist_entry.dart';
import '../../models/history_event.dart';
import '../../models/media_target.dart';
import '../../models/result_page.dart';
import '../capability.dart';
import '../service_result.dart';

/// History and the blocklist. Lists are newest first; pages start at 1.
abstract interface class HistoryProvider implements Capability {
  /// Overall, or for one [target].
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  });

  ServiceResult<void> markFailed(int eventId);

  /// Events after [since], a time taken from the server, not the device.
  ServiceResult<List<HistoryEvent>> eventsSince(DateTime since);

  ServiceResult<ResultPage<BlocklistEntry>> blocklist({int page = 1});

  ServiceResult<void> unblock(List<int> entryIds);
}
