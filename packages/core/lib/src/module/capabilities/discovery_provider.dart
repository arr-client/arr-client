import '../../models/discovery_category.dart';
import '../../models/discovery_ref.dart';
import '../../models/discovery_title.dart';
import '../../models/result_page.dart';
import '../capability.dart';
import '../module_route.dart';
import '../service_result.dart';

/// Discovering titles in a request service. Pages start at 1.
abstract interface class DiscoveryProvider implements Capability {
  ServiceResult<ResultPage<DiscoveryTitle>> discover(
    DiscoveryCategory category, {
    int page = 1,
  });

  ServiceResult<ResultPage<DiscoveryTitle>> search(String term, {int page = 1});

  ServiceResult<DiscoveryTitle> detail(DiscoveryRef ref);

  ModuleRoute entryRoute();

  ModuleRoute detailRoute(DiscoveryTitle title);
}
