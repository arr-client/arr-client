import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'release_view.dart';

/// The filter box and the buttons for the order and the filters.
class ReleaseToolbar extends StatelessWidget {
  const ReleaseToolbar({
    required this.view,
    required this.text,
    required this.onChanged,
    required this.onFilters,
    super.key,
  });

  final ReleaseView view;

  /// The filter box's text.
  final TextEditingController text;

  final ValueChanged<ReleaseView> onChanged;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final filters = view.activeFilters;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: text,
            onChanged: (value) => onChanged(view.copyWith(text: value)),
            textInputAction: TextInputAction.search,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: strings.releasesFilterHint,
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: view.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: strings.libraryClearText,
                      onPressed: () {
                        text.clear();
                        onChanged(view.copyWith(text: ''));
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _SortButton(view: view, onChanged: onChanged),
        IconButton(
          tooltip: filters == 0
              ? strings.libraryFilters
              : strings.libraryFiltersOn(filters),
          onPressed: onFilters,
          icon: Badge.count(
            count: filters,
            isLabelVisible: filters > 0,
            child: const Icon(Icons.filter_list),
          ),
        ),
      ],
    );
  }
}

/// A menu of the fields and the two directions.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.view, required this.onChanged});

  final ReleaseView view;
  final ValueChanged<ReleaseView> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return PopupMenuButton<ReleaseView>(
      tooltip: strings.librarySort,
      icon: const Icon(Icons.sort),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final sort in ReleaseSort.values)
          CheckedPopupMenuItem(
            value: view.copyWith(
              sort: sort,
              ascending: sort == view.sort
                  ? view.ascending
                  : sort.ascendingFirst,
            ),
            checked: sort == view.sort,
            child: Text(switch (sort) {
              ReleaseSort.server => strings.releasesSortServer,
              ReleaseSort.score => strings.releasesSortScore,
              ReleaseSort.seeders => strings.releasesSortSeeders,
              ReleaseSort.size => strings.releasesSortSize,
              ReleaseSort.age => strings.releasesSortAge,
              ReleaseSort.title => strings.librarySortTitle,
            }),
          ),
        // The server's ranking has one direction.
        if (view.sort != ReleaseSort.server) ...[
          const PopupMenuDivider(),
          for (final ascending in const [true, false])
            CheckedPopupMenuItem(
              value: view.copyWith(ascending: ascending),
              checked: view.ascending == ascending,
              child: Text(
                ascending
                    ? strings.librarySortAscending
                    : strings.librarySortDescending,
              ),
            ),
        ],
      ],
    );
  }
}
