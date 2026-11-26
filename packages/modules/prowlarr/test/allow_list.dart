/// Every request the Prowlarr module may make (FR-019), from
/// specs/001-arr-companion-app/contracts/upstream-apis.md, with paths and
/// parameter names as in Prowlarr's v1 API. Adapter tests run through it.
///
/// Anything not here is refused, every configuration write included.
library;

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';

const _any = ParamRule.any();

/// The Prowlarr allow-list.
final allowList = AllowList([
  for (final path in [
    'system/status',
    'health',
    'indexer',
    'indexer/categories',
    'indexerstatus',
  ])
    AllowedRequest.read('api/v1/$path'),
  AllowedRequest.read(
    'api/v1/search',
    query: {
      // Without a term the server answers with its indexers' feeds.
      'query': const ParamRule.nonEmpty(),
      'type': const ParamRule.only({'search'}, required: false),
      'categories': _any,
      'indexerIds': _any,
    },
  ),
  // A grab names the release and nothing else: the addresses a search returns
  // carry keys, and are not sent back.
  AllowedRequest.write(
    HttpMethod.post,
    'api/v1/search',
    body: const BodyRule.jsonObject({
      'guid': ParamRule.nonEmpty(),
      'indexerId': ParamRule.nonEmpty(),
    }, closed: true),
  ),
]);
