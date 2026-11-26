import 'package:core/core.dart';

import 'search_hit.dart';

/// One question to one instance: the capability asked and the instance. An
/// instance can be both a library and a request service.
typedef SearchSource = (CapabilityKind, String instanceId);

/// A source that failed, and the kinds that are missing because of it.
typedef SearchFailure = ({ServiceFailure failure, Set<MediaKind> kinds});

/// What the search screen shows.
final class SearchState {
  const SearchState({
    this.term = '',
    this.hits = const [],
    this.pending = const {},
    this.failures = const {},
  });

  /// What [hits] answer; empty when nothing has been asked.
  final String term;

  /// In the order they first arrived.
  final List<SearchHit> hits;

  /// The sources that have not answered, with the kinds each could give.
  final Map<SearchSource, Set<MediaKind>> pending;

  final Map<SearchSource, SearchFailure> failures;

  bool get isSearching => pending.isNotEmpty;

  List<SearchHit> of(MediaKind kind) => [
    for (final hit in hits)
      if (hit.kind == kind) hit,
  ];
}
