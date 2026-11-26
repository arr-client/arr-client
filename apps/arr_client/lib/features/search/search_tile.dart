import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'search_hit.dart';
import 'search_poster.dart';

/// One result: poster, title, year, overview and the instances that have it.
class SearchTile extends StatelessWidget {
  const SearchTile({
    required this.hit,
    required this.libraries,
    required this.margin,
    required this.onTap,
    super.key,
  });

  final SearchHit hit;

  /// The names of the instances that have the title.
  final List<String> libraries;

  /// The screen margin.
  final double margin;

  /// Null where there is nowhere to go.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final details = [
      ?hit.parentTitle,
      // A year is a name, not a quantity: no digit grouping.
      if (hit.year case final year?) '$year',
    ];
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: margin, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchPoster(hit: hit),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (details.isNotEmpty)
                        Text(details.join(', '), style: quiet),
                      if (hit.overview case final overview?)
                        // One line gives way to the mark, so that a mark that
                        // arrives later does not move the rows below.
                        Text(
                          overview,
                          style: quiet,
                          maxLines: libraries.isEmpty ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (libraries.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: MediaQuery.textScalerOf(context).scale(16),
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                strings.searchInLibrary(libraries.join(', ')),
                                style: theme.textTheme.labelLarge,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
