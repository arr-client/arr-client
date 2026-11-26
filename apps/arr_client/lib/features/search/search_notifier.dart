/// Asks every search source of the active profile and gathers the answers.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'search_hit.dart';
import 'search_state.dart';

/// How long typing has to pause before the services are asked.
const searchDebounce = Duration(milliseconds: 500);

/// Shorter text is searched only when the user submits it, as some titles are a
/// single character.
const searchMinimumLength = 2;

/// The search of the open search screen.
final searchProvider =
    NotifierProvider.autoDispose<SearchNotifier, SearchState>(
      SearchNotifier.new,
    );

// What a request service deals in.
const _discoveryKinds = {MediaKind.movie, MediaKind.series};

/// The kinds the search sources of [scope] can find, in the order shown.
List<MediaKind> searchKinds(ProfileScope scope) {
  final offered = {
    for (final (_, lookup) in scope.providers(CapabilityKind.lookup))
      ...lookup.itemKinds,
    if (scope.providers(CapabilityKind.discovery).isNotEmpty)
      ..._discoveryKinds,
  };
  return [
    for (final kind in MediaKind.values)
      if (offered.contains(kind)) kind,
  ];
}

/// The search as typed.
///
/// A lookup cannot be aborted once sent: what a replaced search still answers is
/// dropped by no longer listening to it.
class SearchNotifier extends Notifier<SearchState> {
  Timer? _debounce;
  final _asking = <StreamSubscription<void>>[];

  /// What is typed, which [state] answers once the debounce has passed.
  var _typed = '';

  /// The sources of the scope, to tell when they are others.
  var _sources = '';

  @override
  SearchState build() {
    ref.onDispose(_stop);
    ref.listen(scopeProvider, (_, scope) => _scopeChanged(scope));
    _sources = _signature(ref.read(scopeProvider));
    return const SearchState();
  }

  /// The text of the field has changed.
  void type(String text) {
    final term = text.trim();
    if (term == _typed) return;
    _typed = term;
    _debounce?.cancel();
    if (term == state.term) return;
    if (term.length < searchMinimumLength) {
      // Results of a longer text no longer belong to the field.
      _clear();
      return;
    }
    _debounce = Timer(searchDebounce, () => _search(term));
  }

  /// Searches [text] now.
  void submit(String text) {
    _typed = text.trim();
    _debounce?.cancel();
    if (_typed.isEmpty) {
      _clear();
    } else if (_typed != state.term) {
      _search(_typed);
    }
  }

  /// Asks the failed sources again, leaving what the others gave where it is.
  void retry() {
    final failed = state.failures.keys.toSet();
    if (failed.isNotEmpty) _ask(state.term, only: failed);
  }

  void _clear() {
    _cancel();
    state = const SearchState();
  }

  void _search(String term) {
    _cancel();
    state = SearchState(term: term);
    _ask(term);
  }

  void _ask(String term, {Set<SearchSource>? only}) {
    final scope = ref.read(scopeProvider);
    // The search runs when there is a scope again.
    if (scope == null) return;
    _askFor(
      scope,
      CapabilityKind.lookup,
      only: only,
      kinds: (lookup) => lookup.itemKinds,
      read: (lookup) => lookup.lookup(term),
      hits: (id, found) => [
        for (final candidate in found) SearchHit.fromLookup(id, candidate),
      ],
    );
    _askFor(
      scope,
      CapabilityKind.discovery,
      only: only,
      kinds: (_) => _discoveryKinds,
      // The first page only.
      read: (discovery) => discovery.search(term),
      hits: (id, page) => [
        for (final title in page.items) SearchHit.fromDiscovery(id, title),
      ],
    );
  }

  void _askFor<T extends Capability, R>(
    ProfileScope scope,
    CapabilityKind<T> capability, {
    required Set<SearchSource>? only,
    required Set<MediaKind> Function(T provider) kinds,
    required ServiceResult<R> Function(T provider) read,
    required List<SearchHit> Function(String instanceId, R value) hits,
  }) {
    // Noted before asking, so that a failure can say what is missing.
    final offered = <String, Set<MediaKind>>{};
    final answered = <String>{};
    final answers = scope.aggregate(
      capability,
      read,
      where: (active, provider) {
        final id = active.instance.id;
        if (only != null && !only.contains((capability, id))) return false;
        offered[id] = kinds(provider);
        return true;
      },
    );
    _asking.add(
      answers.listen((aggregate) {
        final pending = {...state.pending};
        final failures = {...state.failures};
        var found = state.hits;
        for (final part in aggregate.parts) {
          final id = part.instance.instance.id;
          final source = (capability, id);
          // A module that throws while being built is a part that `where` did
          // not see.
          if (only != null && !only.contains(source)) continue;
          if (answered.contains(id)) continue;
          final its = offered[id] ?? const <MediaKind>{};
          switch (part.result) {
            case null:
              pending[source] = its;
              failures.remove(source);
              continue;
            case Ok(:final value):
              failures.remove(source);
              found = mergeHits(found, hits(id, value));
            case Err(:final error):
              failures[source] = (failure: error, kinds: its);
          }
          answered.add(id);
          pending.remove(source);
        }
        state = SearchState(
          term: state.term,
          hits: found,
          pending: pending,
          failures: failures,
        );
      }),
    );
  }

  void _scopeChanged(ProfileScope? scope) {
    final sources = _signature(scope);
    // A scope is also published when only a connection's state changes.
    if (sources == _sources) return;
    _sources = sources;
    // Results of removed or edited instances, or of another profile, go.
    if (state.term.isNotEmpty) _search(state.term);
  }

  /// Which instances would be asked. An edited instance has another client.
  static String _signature(ProfileScope? scope) => [
    if (scope != null) ...[
      scope.profileId,
      for (final active in scope.instances)
        if (active.capabilities.contains(CapabilityKind.lookup) ||
            active.capabilities.contains(CapabilityKind.discovery))
          '${active.instance.id} ${identityHashCode(active.context.http)} '
              '${active.capabilities.contains(CapabilityKind.lookup)} '
              '${active.capabilities.contains(CapabilityKind.discovery)}',
    ],
  ].join('\n');

  void _cancel() {
    for (final subscription in _asking) {
      unawaited(subscription.cancel());
    }
    _asking.clear();
  }

  void _stop() {
    _debounce?.cancel();
    _cancel();
  }
}
