/// The app-wide search (spec story 3, contracts/navigation.md).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/navigation/locations.dart';
import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import 'add_request.dart';
import 'search_failures.dart';
import 'search_hit.dart';
import 'search_notifier.dart';
import 'search_state.dart';
import 'search_tile.dart';

/// A field, and the results grouped by type, one tab for each. In tabs, what
/// arrives for one type moves nothing of another.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = ref.watch(scopeProvider);
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    // While switching profile it is not known what can be searched.
    final kinds = scope == null ? const <MediaKind>[] : searchKinds(scope);

    final appBar = AppBar(
      title: TextField(
        controller: _field,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: strings.searchHint,
          border: InputBorder.none,
        ),
        onChanged: notifier.type,
        onSubmitted: notifier.submit,
      ),
      actions: [
        ListenableBuilder(
          listenable: _field,
          builder: (context, _) => _field.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: strings.searchClear,
                  onPressed: () {
                    _field.clear();
                    notifier.type('');
                    _focus.requestFocus();
                  },
                ),
        ),
      ],
    );

    if (scope == null) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: CircularProgressIndicator(
            semanticsLabel: UiLocalizations.of(context).loading,
          ),
        ),
      );
    }
    if (kinds.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: StateMessage(icon: Icons.search_off, message: strings.notOffered),
      );
    }

    String label(MediaKind kind) => switch (kind) {
      MediaKind.movie => strings.tabMovies,
      MediaKind.series || MediaKind.episode => strings.tabSeries,
      MediaKind.artist => strings.searchArtists,
      MediaKind.album => strings.searchAlbums,
      MediaKind.track => strings.tabMusic,
      MediaKind.author => strings.searchAuthors,
      MediaKind.book => strings.tabBooks,
    };
    String tab(MediaKind kind) => state.term.isEmpty
        ? label(kind)
        : strings.searchTabCount(label(kind), state.of(kind).length);

    final failures = [
      for (final MapEntry(key: (_, id), value: failed)
          in state.failures.entries)
        if (scope.instance(id) case final active?)
          (active.instance.name, failed.failure),
    ];

    return DefaultTabController(
      // Starts over when other types can be searched.
      key: ValueKey(kinds.join()),
      length: kinds.length,
      child: Scaffold(
        appBar: appBar,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final margin = screenMargin(constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (kinds.length > 1)
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [for (final kind in kinds) Tab(text: tab(kind))],
                  ),
                _Progress(state),
                Expanded(
                  child: state.term.isEmpty
                      ? StateMessage(
                          icon: Icons.search,
                          message: strings.searchStart,
                        )
                      : TabBarView(
                          children: [
                            for (final kind in kinds)
                              _Results(
                                // Another search starts at the top.
                                key: PageStorageKey((state.term, kind)),
                                state: state,
                                kind: kind,
                                scope: scope,
                                margin: margin,
                              ),
                          ],
                        ),
                ),
                if (failures.isNotEmpty)
                  ConstrainedBox(
                    // Leaves room for the results at large text sizes.
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.4,
                    ),
                    child: SearchFailures(
                      failures: failures,
                      margin: margin,
                      onRetry: notifier.retry,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A bar while services have yet to answer. Its height stays, so that nothing
/// moves when they have; screen readers then hear how many results there are.
class _Progress extends StatelessWidget {
  const _Progress(this.state);

  static const _height = 4.0;

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (state.isSearching) {
      return LinearProgressIndicator(
        minHeight: _height,
        semanticsLabel: strings.searching,
      );
    }
    if (state.term.isEmpty) return const SizedBox(height: _height);
    return Semantics(
      container: true,
      liveRegion: true,
      label: strings.searchResultCount(state.hits.length),
      child: const SizedBox(height: _height),
    );
  }
}

/// The results of one type.
class _Results extends StatelessWidget {
  const _Results({
    required this.state,
    required this.kind,
    required this.scope,
    required this.margin,
    super.key,
  });

  final SearchState state;
  final MediaKind kind;
  final ProfileScope scope;
  final double margin;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final hits = state.of(kind);
    if (hits.isEmpty) {
      // The bar above says that it is searching.
      if (state.pending.values.any((kinds) => kinds.contains(kind))) {
        return const SizedBox.shrink();
      }
      final failed = state.failures.values.any(
        (failed) => failed.kinds.contains(kind),
      );
      return StateMessage(
        icon: Icons.search_off,
        message: failed
            ? strings.searchNothingFromRest(state.term)
            : strings.searchNothing(state.term),
        announce: true,
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        final holding = {for (final ref in hit.existingRefs) ref.instanceId};
        return SearchTile(
          hit: hit,
          margin: margin,
          libraries: [
            for (final active in scope.instances)
              if (holding.contains(active.instance.id)) active.instance.name,
          ],
          onTap: _open(context, hit),
        );
      },
    );
  }

  /// What a library service found goes to the add flow. What only a request
  /// service knows goes to that service's screen of the title.
  VoidCallback? _open(BuildContext context, SearchHit hit) {
    void push(String location, {Object? extra}) {
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(context.push<void>(location, extra: extra));
    }

    if (hit.canAdd) {
      return () => push(
        addLocation,
        extra: AddRequest(
          hit.candidate,
          artworkInstanceId: hit.artworkInstanceId,
        ),
      );
    }
    for (final MapEntry(key: id, value: title) in hit.discovered.entries) {
      final discovery = scope
          .instance(id)
          ?.capability(CapabilityKind.discovery);
      if (discovery != null) {
        return () => push(discovery.detailRoute(title).location);
      }
    }
    return null;
  }
}
