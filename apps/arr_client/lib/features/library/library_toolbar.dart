import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'library_query.dart';

/// The filter box and the buttons for the order, the filters and the layout.
class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({
    required this.view,
    required this.text,
    required this.activeFilters,
    required this.onText,
    required this.onSort,
    required this.onFilters,
    required this.onLayout,
    this.onSelect,
    super.key,
  });

  final LibraryView view;

  /// The filter box's text.
  final TextEditingController text;

  /// How many filters, besides the text, narrow the library.
  final int activeFilters;

  final ValueChanged<String> onText;
  final ValueChanged<LibrarySort> onSort;
  final VoidCallback onFilters;
  final ValueChanged<LibraryLayout> onLayout;

  /// Starts selecting items; null while there is none to select.
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final grid = view.layout == LibraryLayout.grid;
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = screenMargin(constraints.maxWidth);
        return Padding(
          padding: EdgeInsets.fromLTRB(margin, 8, margin - 8, 4),
          child: Row(
            children: [
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: text,
                  builder: (context, value, _) => TextField(
                    controller: text,
                    onChanged: onText,
                    textInputAction: TextInputAction.search,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                      hintText: strings.libraryFilterHint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: value.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: strings.libraryClearText,
                              onPressed: () {
                                text.clear();
                                onText('');
                              },
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (onSelect != null)
                IconButton(
                  tooltip: strings.selectionStart,
                  onPressed: onSelect,
                  icon: const Icon(Icons.checklist),
                ),
              _SortButton(sort: view.sort, onSort: onSort),
              IconButton(
                tooltip: activeFilters == 0
                    ? strings.libraryFilters
                    : strings.libraryFiltersOn(activeFilters),
                onPressed: onFilters,
                icon: Badge.count(
                  count: activeFilters,
                  isLabelVisible: activeFilters > 0,
                  child: const Icon(Icons.filter_list),
                ),
              ),
              IconButton(
                tooltip: grid
                    ? strings.libraryShowList
                    : strings.libraryShowGrid,
                onPressed: () =>
                    onLayout(grid ? LibraryLayout.list : LibraryLayout.grid),
                icon: Icon(
                  grid ? Icons.view_list_outlined : Icons.grid_view_outlined,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A menu of the fields and the two directions.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onSort});

  final LibrarySort sort;
  final ValueChanged<LibrarySort> onSort;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final current = LibrarySortField.of(sort.field);
    return PopupMenuButton<LibrarySort>(
      tooltip: strings.librarySort,
      icon: const Icon(Icons.sort),
      onSelected: onSort,
      itemBuilder: (context) => [
        for (final field in LibrarySortField.values)
          CheckedPopupMenuItem(
            value: LibrarySort(
              field: field.name,
              ascending: field == current
                  ? sort.ascending
                  : field.ascendingFirst,
            ),
            checked: field == current,
            child: Text(switch (field) {
              LibrarySortField.title => strings.librarySortTitle,
              LibrarySortField.added => strings.librarySortAdded,
              LibrarySortField.year => strings.librarySortYear,
              LibrarySortField.size => strings.librarySortSize,
            }),
          ),
        const PopupMenuDivider(),
        for (final ascending in const [true, false])
          CheckedPopupMenuItem(
            value: LibrarySort(field: current.name, ascending: ascending),
            checked: sort.ascending == ascending,
            child: Text(
              ascending
                  ? strings.librarySortAscending
                  : strings.librarySortDescending,
            ),
          ),
      ],
    );
  }
}
