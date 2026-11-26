/// The requests the shared client may make for the reads tested here.
///
/// `servarr` may not import a module, so this repeats, no wider, the entries of
/// the Radarr and Sonarr allow-lists (`packages/modules/*/test/allow_list.dart`)
/// that these reads use. The modules' lists stay the authority.
library;

import 'package:core/testing/allow_list.dart';

const _any = ParamRule.any();

/// The list for a service whose include-unknown flag is [includeUnknown].
AllowList allowList(String includeUnknown) => AllowList([
  for (final path in [
    'system/status',
    'health',
    'qualityprofile',
    'rootfolder',
    'tag',
  ])
    AllowedRequest.read('api/v3/$path'),
  AllowedRequest.read(
    'api/v3/queue',
    query: {
      'page': _any,
      'pageSize': _any,
      'sortKey': _any,
      'sortDirection': _any,
      includeUnknown: const ParamRule.only({'true'}),
    },
  ),
  AllowedRequest.read(
    'api/v3/history',
    query: {
      'page': _any,
      'pageSize': _any,
      'sortKey': _any,
      'sortDirection': _any,
    },
  ),
  AllowedRequest.read('api/v3/command/{id}'),
]);
