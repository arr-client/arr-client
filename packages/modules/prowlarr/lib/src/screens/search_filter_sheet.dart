import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/prowlarr_localizations.dart';
import 'prowlarr_source.dart';
import 'search_controller.dart';

/// Opens the filters of the search. Each choice applies to [filters] at once;
/// the future completes when the sheet is closed.
Future<void> showSearchFilters(
  BuildContext context, {
  required ProwlarrSource source,
  required ValueNotifier<SearchFilters> filters,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => ValueListenableBuilder(
    valueListenable: filters,
    builder: (context, value, _) => _FilterSheet(
      source: source,
      filters: value,
      onChanged: (changed) => filters.value = changed,
    ),
  ),
);

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({
    required this.source,
    required this.filters,
    required this.onChanged,
  });

  final ProwlarrSource source;
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ProwlarrLocalizations.of(context);
    final theme = Theme.of(context);
    final indexers = ref.watch(indexersProvider(source));
    final categories = ref.watch(categoriesProvider(source));

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );

    // Chips for what there is, by id.
    Widget chips(
      Map<int, String> choices,
      Set<int> chosen,
      SearchFilters Function(Set<int> chosen) apply,
    ) => Wrap(
      spacing: 8,
      children: [
        for (final MapEntry(key: id, value: name) in choices.entries)
          FilterChip(
            label: Text(name),
            selected: chosen.contains(id),
            onSelected: (on) => onChanged(
              apply(on ? {...chosen, id} : chosen.difference({id})),
            ),
          ),
      ],
    );

    Widget failed(ServiceFailure failure, VoidCallback retry) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(failureMessage(context, failure)),
        ),
        TextButton(
          onPressed: retry,
          child: Text(UiLocalizations.of(context).retry),
        ),
      ],
    );

    final loading = LinearProgressIndicator(
      semanticsLabel: UiLocalizations.of(context).loading,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = screenMargin(constraints.maxWidth);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The categories are many: the buttons stay below what scrolls.
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: margin),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        strings.filters,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(strings.filtersNoneChosen),
                    heading(strings.filterIndexers),
                    switch (indexers) {
                      ViewLoading() => loading,
                      ViewError(:final failure) => failed(
                        failure,
                        () => unawaited(
                          ref.read(indexersProvider(source).notifier).refresh(),
                        ),
                      ),
                      ViewData(:final value) => chips(
                        {
                          // One turned off cannot be searched.
                          for (final indexer in value)
                            if (indexer.enabled ||
                                filters.indexerIds.contains(indexer.id))
                              indexer.id: serverText(indexer.name) ?? '',
                        },
                        filters.indexerIds,
                        (chosen) => SearchFilters(
                          categoryIds: filters.categoryIds,
                          indexerIds: chosen,
                        ),
                      ),
                    },
                    heading(strings.filterCategories),
                    switch (categories) {
                      AsyncData(value: Ok(:final value)) => chips(
                        {
                          for (final category in value)
                            category.id: serverText(category.name) ?? '',
                        },
                        filters.categoryIds,
                        (chosen) => SearchFilters(
                          categoryIds: chosen,
                          indexerIds: filters.indexerIds,
                        ),
                      ),
                      AsyncData(value: Err(:final error))
                          when !categories.isLoading =>
                        failed(
                          error,
                          () => ref.invalidate(categoriesProvider(source)),
                        ),
                      _ => loading,
                    },
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                margin,
                8,
                margin,
                16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  TextButton(
                    onPressed: filters.count == 0
                        ? null
                        : () => onChanged(const SearchFilters()),
                    child: Text(strings.filtersClear),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(strings.filtersDone),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
