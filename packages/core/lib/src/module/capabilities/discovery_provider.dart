import '../../models/discovery_category.dart';
import '../../models/discovery_ref.dart';
import '../../models/discovery_title.dart';
import '../../models/result_page.dart';
import '../capability.dart';
import '../module_route.dart';
import '../service_result.dart';

/// Discovering titles in a request service. Pages start at 1.
abstract interface class DiscoveryProvider implements Capability {
  /// One browsable list.
  ServiceResult<ResultPage<DiscoveryTitle>> discover(
    DiscoveryCategory category, {
    int page = 1,
  });

  /// Titles matching [term].
  ServiceResult<ResultPage<DiscoveryTitle>> search(String term, {int page = 1});

  /// One title with its current availability.
  ServiceResult<DiscoveryTitle> detail(DiscoveryRef ref);

  /// The discovery screen.
  ModuleRoute entryRoute();

  /// The screen of [title].
  ModuleRoute detailRoute(DiscoveryTitle title);
}
