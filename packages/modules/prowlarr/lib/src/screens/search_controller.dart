/// What the search screen reads. Nothing of it is saved on the device: results
/// hold keys in their addresses.
library;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'grabs.dart';
import 'prowlarr_source.dart';

/// What a search is narrowed to. An empty set narrows nothing.
@immutable
final class SearchFilters {
  /// Creates [SearchFilters].
  const SearchFilters({
    this.categoryIds = const {},
    this.indexerIds = const {},
  });

  /// The categories searched.
  final Set<int> categoryIds;

  /// The indexers searched.
  final Set<int> indexerIds;

  /// How many of the two filters are on.
  int get count => (categoryIds.isEmpty ? 0 : 1) + (indexerIds.isEmpty ? 0 : 1);

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      setEquals(other.categoryIds, categoryIds) &&
      setEquals(other.indexerIds, indexerIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(categoryIds),
    Object.hashAllUnordered(indexerIds),
  );
}

/// One search asked for.
typedef SearchQuery = ({String term, SearchFilters filters});

/// What is known of the search last asked for.
final class SearchState {
  /// Creates a [SearchState].
  const SearchState({
    this.query,
    this.listing,
    this.results,
    this.fetchedAt,
    this.failure,
    this.searching = false,
  });

  /// What was asked for; null before the first search.
  final SearchQuery? query;

  /// Stands for the list of results of [query]: the same while that query is
  /// searched again, another for another query. The list's place is kept
  /// under it.
  final Object? listing;

  /// As last found for [query], in the server's order; null if it has not
  /// succeeded.
  final List<Release>? results;

  /// When [results] was found.
  final DateTime? fetchedAt;

  /// Why the last search failed; null if it succeeded or is under way.
  final ServiceFailure? failure;

  /// Whether a search is under way.
  final bool searching;
}

/// The search of one instance, while its screen is open.
final searchProvider = NotifierProvider.autoDispose
    .family<SearchController, SearchState, ProwlarrSource>(
      SearchController.new,
    );

/// Searches when the user asks. Only the newest search is believed.
final class SearchController extends Notifier<SearchState> {
  /// For [source].
  SearchController(this.source);

  /// What is searched.
  final ProwlarrSource source;

  // Counts the searches.
  var _search = 0;

  @override
  SearchState build() => const SearchState();

  /// Searches for [query]. A blank term, or the query already being searched
  /// for, sends nothing.
  Future<void> search(SearchQuery query) async {
    if (query.term.trim().isEmpty) return;
    if (state.searching && state.query == query) return;
    final search = ++_search;
    // What was found for another query goes; what was found for this one stays
    // until the server answers.
    final same = state.query == query;
    final listing = same ? state.listing : Object();
    final results = same ? state.results : null;
    final fetchedAt = same ? state.fetchedAt : null;
    ref.read(grabsProvider.notifier).forgetAccepted(source.instanceId);
    state = SearchState(
      query: query,
      listing: listing,
      results: results,
      fetchedAt: fetchedAt,
      searching: true,
    );
    final answer = await source.guard(
      () => source.provider.search(
        query.term.trim(),
        categoryIds: query.filters.categoryIds,
        indexerIds: query.filters.indexerIds,
      ),
    );
    if (!ref.mounted || search != _search) return;
    state = switch (answer) {
      Ok(:final value) => SearchState(
        query: query,
        listing: listing,
        results: List.unmodifiable(value),
        fetchedAt: DateTime.now(),
      ),
      Err(:final error) => SearchState(
        query: query,
        listing: listing,
        results: results,
        fetchedAt: fetchedAt,
        // The server's own words can quote an indexer's address.
        failure: error is Validation ? const Validation([]) : error,
      ),
    };
  }

  /// Repeats the last search.
  Future<void> retry() async {
    if (state.query case final query?) await search(query);
  }
}

/// The categories of one instance, for the filters.
final categoriesProvider = FutureProvider.autoDispose
    .family<Result<List<IndexerCategory>, ServiceFailure>, ProwlarrSource>(
      (ref, source) => source.guard(source.provider.categories),
    );

/// The indexers of one instance with their status, while a screen shows them.
final indexersProvider = NotifierProvider.autoDispose
    .family<IndexersController, ViewState<List<Indexer>>, ProwlarrSource>(
      IndexersController.new,
    );

/// Reads the indexers when first asked for and on refresh. What was read stays,
/// with its age, if a later read fails.
final class IndexersController extends Notifier<ViewState<List<Indexer>>> {
  /// For [source].
  IndexersController(this.source);

  /// Whose indexers.
  final ProwlarrSource source;

  DateTime _fetchedAt = DateTime.now();
  Future<void>? _loading;

  @override
  ViewState<List<Indexer>> build() {
    // Not at once: there is no state to change until this returns.
    _loading = Future.microtask(_fetch);
    return const ViewLoading();
  }

  /// Reads again. A read already under way is not repeated.
  Future<void> refresh() {
    if (_loading case final loading?) return loading;
    switch (state) {
      // The old failure goes while the server is asked again.
      case ViewData(:final value, staleness: Staleness()):
        state = ViewData(value, staleness: Staleness(fetchedAt: _fetchedAt));
      case ViewError():
        state = const ViewLoading();
      case ViewData() || ViewLoading():
        break;
    }
    return _loading = _fetch();
  }

  Future<void> _fetch() async {
    if (!ref.mounted) return;
    final answer = await source.guard(source.provider.indexers);
    if (!ref.mounted) return;
    _loading = null;
    switch (answer) {
      case Ok(:final value):
        _fetchedAt = DateTime.now();
        state = ViewData(value);
      case Err(:final error):
        state = switch (state) {
          ViewData(:final value) => ViewData(
            value,
            staleness: Staleness(fetchedAt: _fetchedAt, failure: error),
          ),
          ViewLoading() || ViewError() => ViewError(error),
        };
    }
  }
}
