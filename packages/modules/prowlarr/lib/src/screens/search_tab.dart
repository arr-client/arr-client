import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/prowlarr_localizations.dart';
import 'grabs.dart';
import 'prowlarr_source.dart';
import 'search_controller.dart';
import 'search_filter_sheet.dart';

/// The order of the results shown.
typedef ResultOrder = ({ReleaseSort sort, bool ascending});

/// The free-text search: the box, the order and filters, and the results.
class SearchTab extends ConsumerWidget {
  /// Creates a [SearchTab]. Its notifiers belong to the screen, so that they
  /// are kept while another tab is shown.
  const SearchTab({
    required this.source,
    required this.term,
    required this.filters,
    required this.order,
    required this.onGrab,
    super.key,
  });

  /// What is searched.
  final ProwlarrSource source;

  /// The search box's text.
  final TextEditingController term;

  /// What the next search is narrowed to.
  final ValueNotifier<SearchFilters> filters;

  /// How the results are ordered.
  final ValueNotifier<ResultOrder> order;

  /// Grabs a result.
  final void Function(Release release) onGrab;

  void _search(WidgetRef ref) {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(
      ref.read(searchProvider(source).notifier).search((
        term: term.text.trim(),
        filters: filters.value,
      )),
    );
  }

  Future<void> _filter(BuildContext context, WidgetRef ref) async {
    final before = filters.value;
    final controller = ref.read(searchProvider(source).notifier);
    await showSearchFilters(context, source: source, filters: filters);
    // The results shown are always those of the filters chosen.
    if (!context.mounted || filters.value == before) return;
    final query = ref.read(searchProvider(source)).query;
    if (query != null) {
      await controller.search((term: query.term, filters: filters.value));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ProwlarrLocalizations.of(context);
    final search = ref.watch(searchProvider(source));
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = screenMargin(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(margin, 8, margin, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: term,
                      onSubmitted: (_) => _search(ref),
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: InputDecoration(
                        labelText: strings.searchTerm,
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: strings.searchSubmit,
                          onPressed: () => _search(ref),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ValueListenableBuilder(
                    valueListenable: order,
                    builder: (context, value, _) => ReleaseSortButton(
                      choices: const [
                        ReleaseSort.server,
                        ReleaseSort.title,
                        ReleaseSort.indexer,
                        ReleaseSort.size,
                        ReleaseSort.age,
                        ReleaseSort.seeders,
                      ],
                      sort: value.sort,
                      ascending: value.ascending,
                      onChanged: (sort, ascending) =>
                          order.value = (sort: sort, ascending: ascending),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: filters,
                    builder: (context, value, _) => IconButton(
                      tooltip: value.count == 0
                          ? strings.filters
                          : strings.filtersOn(value.count),
                      onPressed: () => unawaited(_filter(context, ref)),
                      icon: Badge.count(
                        count: value.count,
                        isLabelVisible: value.count > 0,
                        child: const Icon(Icons.filter_list),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _content(context, ref, search)),
          ],
        );
      },
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, SearchState search) {
    final strings = ProwlarrLocalizations.of(context);
    void retry() =>
        unawaited(ref.read(searchProvider(source).notifier).retry());
    if (search.query == null) {
      return StateMessage(
        icon: Icons.manage_search,
        message: strings.searchStart,
      );
    }
    final results = search.results;
    final fetchedAt = search.fetchedAt;
    final failure = search.failure;
    if (results == null && search.searching) {
      return ProgressMessage(message: strings.searching);
    }
    if (results == null && failure is Validation) {
      return StateMessage(
        icon: Icons.error_outline,
        message: strings.searchRefused,
        announce: true,
        action: FilledButton(
          onPressed: retry,
          child: Text(UiLocalizations.of(context).retry),
        ),
      );
    }
    return StateScaffold<List<Release>>(
      state: results != null && fetchedAt != null
          ? ViewData(
              results,
              // Nothing is grabbed from results that are being replaced.
              staleness: search.searching || failure != null
                  ? Staleness(fetchedAt: fetchedAt, failure: failure)
                  : null,
            )
          : ViewError(failure ?? const MalformedResponse()),
      onRetry: retry,
      isEmpty: (results) => results.isEmpty,
      emptyMessage: strings.searchNone,
      builder: (context, results, {required isStale}) => _Results(
        // Kept over a change of tab. Another query's results have another
        // key, so they start at the top.
        key: PageStorageKey(search.listing),
        source: source,
        results: results,
        order: order,
        onGrab: isStale ? null : onGrab,
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.source,
    required this.results,
    required this.order,
    required this.onGrab,
    super.key,
  });

  final ProwlarrSource source;
  final List<Release> results;
  final ValueNotifier<ResultOrder> order;

  /// Null while nothing may be grabbed.
  final void Function(Release release)? onGrab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ProwlarrLocalizations.of(context);
    final marks = ref.watch(grabsProvider);
    return ValueListenableBuilder(
      valueListenable: order,
      builder: (context, value, _) {
        final shown = sortReleases(
          results,
          value.sort,
          ascending: value.ascending,
        );
        return LayoutBuilder(
          builder: (context, constraints) => ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: screenMargin(constraints.maxWidth),
              vertical: 8,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            // The count comes first.
            itemCount: shown.length + 1,
            separatorBuilder: (context, index) =>
                index == 0 ? const SizedBox.shrink() : const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(strings.searchCount(shown.length));
              }
              final release = shown[index - 1];
              return ReleaseRow(
                key: ObjectKey(release),
                release: release,
                mark: marks[grabKey(source.instanceId, release)],
                unknownNote: strings.grabUnknown,
                showScore: false,
                onGrab: switch (onGrab) {
                  final grab? => () => grab(release),
                  null => null,
                },
              );
            },
          ),
        );
      },
    );
  }
}
