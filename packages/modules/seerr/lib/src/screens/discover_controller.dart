/// The titles the discover screen lists.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'seerr_source.dart';
import 'title_news.dart';

/// What is listed: the titles matching [term], or else those of [category].
typedef DiscoverQuery = ({DiscoveryCategory category, String term});

/// What is known of the list asked for.
final class DiscoverState {
  /// Creates a [DiscoverState].
  const DiscoverState({
    required this.query,
    required this.listing,
    this.items,
    this.page = 0,
    this.hasMore = false,
    this.fetchedAt,
    this.failure,
    this.loading = false,
    this.loadingMore = false,
    this.moreFailure,
  });

  /// What was asked for.
  final DiscoverQuery query;

  /// Stands for the list of [query]: its place is kept under it.
  final Object listing;

  /// Null until a read has succeeded.
  final List<DiscoveryTitle>? items;

  /// The last page read.
  final int page;

  /// Whether another page follows.
  final bool hasMore;

  /// When the first page was read.
  final DateTime? fetchedAt;

  /// Why the first page could not be read.
  final ServiceFailure? failure;

  /// Whether the first page is being read.
  final bool loading;

  /// Whether a further page is being read.
  final bool loadingMore;

  /// Why a further page could not be read.
  final ServiceFailure? moreFailure;

  /// This list with what is given changed. The failures and the flags are not
  /// carried over.
  DiscoverState _with({
    List<DiscoveryTitle>? items,
    int? page,
    bool? hasMore,
    DateTime? fetchedAt,
    ServiceFailure? failure,
    bool loading = false,
    bool loadingMore = false,
    ServiceFailure? moreFailure,
  }) => DiscoverState(
    query: query,
    listing: listing,
    items: items ?? this.items,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    failure: failure,
    loading: loading,
    loadingMore: loadingMore,
    moreFailure: moreFailure,
  );
}

/// The list of one instance, while its screen is open.
final discoverProvider = NotifierProvider.autoDispose
    .family<DiscoverController, DiscoverState, SeerrSource>(
      DiscoverController.new,
    );

/// Reads the list asked for, a page at a time. Only the newest read is
/// believed.
final class DiscoverController extends Notifier<DiscoverState> {
  /// For [source].
  DiscoverController(this.source);

  /// What is browsed.
  final SeerrSource source;

  // Counts the reads of a first page.
  var _load = 0;

  @override
  DiscoverState build() {
    ref.listen(readTitleProvider(source), (_, title) {
      if (title != null) _replace(title);
    });
    // Not at once: there is no state to change until this returns.
    Future.microtask(refresh);
    return DiscoverState(
      query: (category: DiscoveryCategory.trending, term: ''),
      listing: Object(),
      loading: true,
    );
  }

  /// Lists what [query] names. What is listed already is left as it is.
  Future<void> show(DiscoverQuery query) async {
    if (query == state.query) return;
    state = DiscoverState(query: query, listing: Object(), loading: true);
    await refresh();
  }

  /// Reads the first page again; what was read stays until the server answers.
  Future<void> refresh() async {
    if (!ref.mounted) return;
    final load = ++_load;
    state = state._with(loading: true);
    final answer = await _read(1);
    if (!ref.mounted || load != _load) return;
    state = switch (answer) {
      Ok(:final value) => state._with(
        items: List.unmodifiable(value.items),
        page: value.page,
        hasMore: value.hasMore,
        fetchedAt: DateTime.now(),
      ),
      Err(:final error) => state._with(failure: error),
    };
  }

  /// Reads the next page, if there is one and none is being read.
  Future<void> more() async {
    final before = state;
    if (before.items == null ||
        !before.hasMore ||
        before.loading ||
        before.loadingMore) {
      return;
    }
    final load = _load;
    state = before._with(failure: before.failure, loadingMore: true);
    final answer = await _read(before.page + 1);
    if (!ref.mounted || load != _load) return;
    final items = state.items!;
    switch (answer) {
      case Ok(:final value):
        // The pages of a changing list can overlap.
        final seen = {for (final title in items) _refOf(title)};
        state = state._with(
          items: List.unmodifiable([
            ...items,
            for (final title in value.items)
              if (seen.add(_refOf(title))) title,
          ]),
          page: value.page,
          hasMore: value.hasMore,
          failure: state.failure,
        );
      case Err(:final error):
        state = state._with(failure: state.failure, moreFailure: error);
    }
  }

  // Shows [title] as its own page has just read it.
  void _replace(DiscoveryTitle title) {
    final items = state.items;
    if (items == null) return;
    state = state._with(
      items: List.unmodifiable([
        for (final item in items) _refOf(item) == _refOf(title) ? title : item,
      ]),
      failure: state.failure,
      loading: state.loading,
      loadingMore: state.loadingMore,
      moreFailure: state.moreFailure,
    );
  }

  ServiceResult<ResultPage<DiscoveryTitle>> _read(int page) {
    final (:category, :term) = state.query;
    return source.guard(
      () => term.isEmpty
          ? source.discovery.discover(category, page: page)
          : source.discovery.search(term, page: page),
    );
  }

  static DiscoveryRef _refOf(DiscoveryTitle title) =>
      DiscoveryRef(mediaType: title.mediaType, tmdbId: title.tmdbId);
}
