import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';
import 'release_sort.dart';

/// A menu of the fields releases can be ordered by, and the two directions.
class ReleaseSortButton extends StatelessWidget {
  /// Creates a [ReleaseSortButton].
  const ReleaseSortButton({
    required this.choices,
    required this.sort,
    required this.ascending,
    required this.onChanged,
    super.key,
  });

  /// The fields offered, in their order.
  final List<ReleaseSort> choices;

  /// The field chosen.
  final ReleaseSort sort;

  /// The direction chosen.
  final bool ascending;

  /// Called with what the user chose.
  final void Function(ReleaseSort sort, bool ascending) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = UiLocalizations.of(context);
    return PopupMenuButton<(ReleaseSort, bool)>(
      tooltip: strings.releaseSortTooltip,
      icon: const Icon(Icons.sort),
      onSelected: (choice) => onChanged(choice.$1, choice.$2),
      itemBuilder: (context) => [
        for (final choice in choices)
          CheckedPopupMenuItem(
            value: (choice, choice == sort ? ascending : choice.ascendingFirst),
            checked: choice == sort,
            child: Text(switch (choice) {
              ReleaseSort.server => strings.releaseSortServer,
              ReleaseSort.score => strings.releaseSortScore,
              ReleaseSort.seeders => strings.releaseSortSeeders,
              ReleaseSort.size => strings.releaseSortSize,
              ReleaseSort.age => strings.releaseSortAge,
              ReleaseSort.title => strings.releaseSortTitle,
              ReleaseSort.indexer => strings.releaseSortIndexer,
            }),
          ),
        // The server's ranking has one direction.
        if (sort != ReleaseSort.server) ...[
          const PopupMenuDivider(),
          for (final direction in const [true, false])
            CheckedPopupMenuItem(
              value: (sort, direction),
              checked: ascending == direction,
              child: Text(
                direction
                    ? strings.releaseSortAscending
                    : strings.releaseSortDescending,
              ),
            ),
        ],
      ],
    );
  }
}
