/// One item of a library, as a poster in the grid or a row of the list. Both
/// give their height from the text size, so that thousands of them can be laid
/// out without building them.
library;

import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'library_entry.dart';
import 'library_poster.dart';
import 'library_query.dart';
import 'state_appearance.dart';

/// The height of one line of [style] at the viewer's text size.
double _line(BuildContext context, TextStyle style) =>
    (MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14) *
            (style.height ?? 1.5))
        .ceilToDouble();

/// The icon beside the state grows with the text.
double _iconSize(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14);

/// In the grid's narrow tiles, large text gives the state a second line.
int _stateLines(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3 ? 2 : 1;

/// Everything the tile says, as one node for a screen reader that opens it.
class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap, required this.child});

  final List<String?> label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label.nonNulls.join(', '),
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: child,
    ),
  );
}

class _StateLine extends StatelessWidget {
  const _StateLine(this.state, {this.lines = 1});

  final ItemState state;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          state.icon,
          size: _iconSize(context),
          color: state.color(theme.colorScheme),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            state.label(AppLocalizations.of(context)),
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// A poster with the title and state under it, and the instance's name when
/// [instanceName] is given.
class LibraryGridTile extends StatelessWidget {
  const LibraryGridTile({
    required this.entry,
    required this.artwork,
    required this.width,
    required this.onTap,
    this.instanceName,
    super.key,
  });

  final LibraryEntry entry;
  final ArtworkLoader artwork;
  final double width;
  final VoidCallback onTap;
  final String? instanceName;

  /// The height of a tile [width] wide: the poster, two lines of title, the
  /// state and, if shown, the instance.
  static double height(
    BuildContext context,
    double width, {
    required bool showsInstance,
  }) {
    return width * 1.5 +
        4 +
        _captionHeight(context, showsInstance: showsInstance);
  }

  static double _captionHeight(
    BuildContext context, {
    required bool showsInstance,
  }) {
    final text = Theme.of(context).textTheme;
    return 2 * _line(context, text.bodyMedium!) +
        math.max(
          _stateLines(context) * _line(context, text.bodySmall!),
          _iconSize(context),
        ) +
        (showsInstance ? _line(context, text.labelSmall!) : 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = entry.item;
    return _Tile(
      label: [
        item.title,
        if (item.year case final year?) '$year',
        item.state.label(AppLocalizations.of(context)),
        instanceName,
      ],
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LibraryPoster(item: item, artwork: artwork, width: width),
            ),
          ),
          const SizedBox(height: 4),
          // The same height whatever the title, so that the posters of a row
          // line up; a title of one line leaves the room below.
          SizedBox(
            height: _captionHeight(
              context,
              showsInstance: instanceName != null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                _StateLine(item.state, lines: _stateLines(context)),
                if (instanceName case final name?)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row with a small poster, the title, a line of details and the state.
class LibraryListTile extends StatelessWidget {
  const LibraryListTile({
    required this.entry,
    required this.artwork,
    required this.sortField,
    required this.onTap,
    this.instanceName,
    super.key,
  });

  final LibraryEntry entry;
  final ArtworkLoader artwork;

  /// What the list is ordered by, whose value the row then shows.
  final LibrarySortField sortField;
  final VoidCallback onTap;
  final String? instanceName;

  static const _posterWidth = 56.0;

  /// The height of every row.
  static double height(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lines =
        2 * _line(context, text.bodyLarge!) +
        _line(context, text.bodySmall!) +
        math.max(_line(context, text.bodySmall!), _iconSize(context));
    return math.max(lines, _posterWidth * 1.5) + 16;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = entry.item;
    // Missing values are left out.
    final details = [
      if (item.year case final year?) '$year',
      if (sortField == LibrarySortField.added)
        if (item.addedAt case final added?)
          MaterialLocalizations.of(context).formatShortDate(added.toLocal()),
      if (sortField == LibrarySortField.size && item.sizeOnDisk > 0)
        formatBytes(context, item.sizeOnDisk),
      ?instanceName,
    ];
    return _Tile(
      label: [
        item.title,
        ...details,
        item.state.label(AppLocalizations.of(context)),
      ],
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenMargin(constraints.maxWidth),
            vertical: 8,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: _posterWidth,
                  height: _posterWidth * 1.5,
                  child: LibraryPoster(
                    item: item,
                    artwork: artwork,
                    width: _posterWidth,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    _StateLine(item.state),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
