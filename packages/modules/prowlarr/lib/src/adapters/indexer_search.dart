import 'package:core/core.dart';
import 'package:servarr/servarr.dart';

import '../models/indexer_records.dart';
import '../search_route.dart';

/// Indexer search for one instance of Prowlarr.
///
/// Search results carry the indexers' passkeys and Prowlarr's own API key in
/// their addresses and guids, so nothing of them is logged or cached.
final class ProwlarrIndexerSearchAdapter implements IndexerSearchProvider {
  /// The search of the instance [instanceId], through [_client].
  ProwlarrIndexerSearchAdapter(this._client, this.instanceId);

  final ServarrClient _client;

  /// The instance searched.
  final String instanceId;

  @override
  ServiceResult<List<Indexer>> indexers() async {
    // The status first, so that the list can be read in one go.
    switch (await _client.read('indexerstatus', indexerFailures)) {
      case Err(:final error):
        return Err(error);
      case Ok(value: final failures):
        return _client.read(
          'indexer',
          (json) => indexerRecords(json, failures),
        );
    }
  }

  @override
  ServiceResult<List<IndexerCategory>> categories() =>
      _client.read('indexer/categories', categoryRecords);

  /// A blank [term] sends nothing and fails with [Validation]: the server
  /// would answer with its indexers' feeds.
  @override
  ServiceResult<List<Release>> search(
    String term, {
    Set<int> categoryIds = const {},
    Set<int> indexerIds = const {},
  }) async {
    if (term.trim().isEmpty) return const Err(Validation([]));
    return _client.textSearch({
      'query': [term],
      'type': ['search'],
      if (categoryIds.isNotEmpty)
        'categories': [for (final id in categoryIds) '$id'],
      if (indexerIds.isNotEmpty)
        'indexerIds': [for (final id in indexerIds) '$id'],
    });
  }

  @override
  ServiceResult<void> grab(Release release) =>
      _client.grab(release, path: 'search');

  @override
  ModuleRoute entryRoute() =>
      ModuleRoute(instanceId: instanceId, path: searchPattern);
}
