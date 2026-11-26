import '../../models/indexer.dart';
import '../../models/indexer_category.dart';
import '../../models/release.dart';
import '../capability.dart';
import '../module_route.dart';
import '../service_result.dart';

/// Free-text search across indexers.
abstract interface class IndexerSearchProvider implements Capability {
  /// Indexers and their status.
  ServiceResult<List<Indexer>> indexers();

  /// Categories to filter by.
  ServiceResult<List<IndexerCategory>> categories();

  /// Empty filters mean all.
  ServiceResult<List<Release>> search(
    String term, {
    Set<int> categoryIds = const {},
    Set<int> indexerIds = const {},
  });

  /// Sends [release] to a download client.
  ServiceResult<void> grab(Release release);

  /// The indexer search screen.
  ModuleRoute entryRoute();
}
