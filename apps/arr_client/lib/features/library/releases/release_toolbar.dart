import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

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
        ReleaseSortButton(
          choices: const [
            ReleaseSort.server,
            ReleaseSort.score,
            ReleaseSort.seeders,
            ReleaseSort.size,
            ReleaseSort.age,
            ReleaseSort.title,
          ],
          sort: view.sort,
          ascending: view.ascending,
          onChanged: (sort, ascending) =>
              onChanged(view.copyWith(sort: sort, ascending: ascending)),
        ),
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
