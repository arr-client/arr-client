import '../../models/indexer.dart';
import '../../models/indexer_category.dart';
import '../../models/release.dart';
import '../capability.dart';
import '../module_route.dart';
import '../service_result.dart';

/// Free-text search across indexers.
abstract interface class IndexerSearchProvider implements Capability {
  ServiceResult<List<Indexer>> indexers();

  ServiceResult<List<IndexerCategory>> categories();

  /// Empty filters mean all.
  ServiceResult<List<Release>> search(
    String term, {
    Set<int> categoryIds = const {},
    Set<int> indexerIds = const {},
  });

  ServiceResult<void> grab(Release release);

  ModuleRoute entryRoute();
}
