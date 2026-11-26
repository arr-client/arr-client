import '../../models/command.dart';
import '../../models/import_choices.dart';
import '../../models/manual_import_candidate.dart';
import '../../models/queue_item.dart';
import '../../models/remove_options.dart';
import '../capability.dart';
import '../service_result.dart';

/// The download queue and manual import.
abstract interface class QueueProvider implements Capability {
  /// The whole queue, including downloads the server cannot match.
  ServiceResult<List<QueueItem>> queue();

  ServiceResult<void> remove(int queueId, RemoveOptions options);

  ServiceResult<void> removeMany(List<int> queueIds, RemoveOptions options);

  /// Grabs a delayed item at once.
  ServiceResult<void> grabNow(int queueId);

  ServiceResult<List<ManualImportCandidate>> importCandidates(QueueItem item);

  ServiceResult<ImportChoices> importChoices();

  /// Has the server evaluate corrected candidates again.
  ServiceResult<List<ManualImportCandidate>> reprocess(
    List<ManualImportCandidate> candidates,
  );

  /// The contract's `import`.
  ServiceResult<Command> importFiles(List<ManualImportCandidate> candidates);
}
