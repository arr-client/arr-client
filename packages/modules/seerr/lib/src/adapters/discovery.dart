import 'package:core/core.dart';

import '../api/seerr_api.dart';
import '../routes.dart';
import 'records.dart';
import 'server.dart';

/// Browsing and searching one instance of Seerr, Overseerr or Jellyseerr.
final class SeerrDiscoveryAdapter implements DiscoveryProvider {
  SeerrDiscoveryAdapter(InstanceContext context)
    : _api = SeerrApi(context),
      _server = SeerrServer.of(context.instance.lastProbe),
      _instanceId = context.instance.id;

  final SeerrApi _api;
  final SeerrServer _server;
  final String _instanceId;

  @override
  ServiceResult<ResultPage<DiscoveryTitle>> discover(
    DiscoveryCategory category, {
    int page = 1,
  }) => _page(switch (category) {
    DiscoveryCategory.trending => 'discover/trending',
    DiscoveryCategory.popularMovies => 'discover/movies',
    DiscoveryCategory.popularSeries => 'discover/tv',
    DiscoveryCategory.upcomingMovies => 'discover/movies/upcoming',
    DiscoveryCategory.upcomingSeries => 'discover/tv/upcoming',
  }, page);

  /// A blank [term] sends nothing and fails with [Validation].
  @override
  ServiceResult<ResultPage<DiscoveryTitle>> search(
    String term, {
    int page = 1,
  }) async {
    if (term.trim().isEmpty) return const Err(Validation([]));
    // As typed: the client encodes it.
    return _page(
      'search',
      page,
      query: {
        'query': [term],
      },
    );
  }

  /// One page of titles. People and collections are left out.
  ServiceResult<ResultPage<DiscoveryTitle>> _page(
    String path,
    int page, {
    Map<String, List<String>> query = const {},
  }) async {
    final answer = await readRecord(
      _api,
      path,
      (object) => (
        results: [
          for (final result in asObjects(object['results']))
            if (mediaTypeOf(result['mediaType']) != null) result,
        ],
        hasMore: page < requireInt(object, 'totalPages'),
      ),
      query: {
        ...query,
        'page': ['$page'],
      },
    );
    switch (answer) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final cacheImages = await _cacheImages(value.results);
        return reading(
          () => ResultPage(
            items: [
              for (final result in value.results)
                discoveryTitle(
                  result,
                  mediaTypeOf(result['mediaType'])!,
                  server: _server,
                  cacheImages: cacheImages,
                ),
            ],
            page: page,
            hasMore: value.hasMore,
          ),
        );
    }
  }

  @override
  ServiceResult<DiscoveryTitle> detail(DiscoveryRef ref) async {
    final answer = await readRecord(
      _api,
      '${wireName(ref.mediaType)}/${ref.tmdbId}',
      (object) => object,
    );
    switch (answer) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final cacheImages = await _cacheImages([value]);
        return reading(
          () => discoveryTitle(
            value,
            ref.mediaType,
            server: _server,
            cacheImages: cacheImages,
          ),
        );
    }
  }

  /// Whether the instance serves the posters of [titles] itself. Null where
  /// there are none, or it cannot be learnt: the titles are then shown without
  /// them rather than not at all, and no public host is asked in its place.
  Future<bool?> _cacheImages(List<JsonObject> titles) async {
    if (titles.every((title) => title['posterPath'] == null)) return null;
    return switch (await _api.readObject('settings/public')) {
      Ok(:final value) => value['cacheImages'] == true,
      Err() => null,
    };
  }

  @override
  ModuleRoute entryRoute() =>
      ModuleRoute(instanceId: _instanceId, path: discoverPattern);

  @override
  ModuleRoute detailRoute(DiscoveryTitle title) => ModuleRoute(
    instanceId: _instanceId,
    path: titlePath(titlePattern, title),
  );
}
