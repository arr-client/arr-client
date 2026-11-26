import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import '../library/state_appearance.dart';
import 'wanted_controller.dart';

/// What names [item] among all others: an episode also by its series and
/// number.
String wantedItemName(AppLocalizations strings, LibraryItem item) =>
    switch (item) {
      Episode() => '${_title(strings, item)} ${_number(strings, item)}',
      _ => _title(strings, item),
    };

String _title(AppLocalizations strings, LibraryItem item) {
  final title = switch (item) {
    Episode(:final parentTitle?) => parentTitle,
    _ => item.title,
  };
  return title.isEmpty ? strings.wantedNoTitle : title;
}

String _number(AppLocalizations strings, Episode episode) =>
    strings.wantedEpisodeNumber(
      '${episode.seasonNumber}'.padLeft(2, '0'),
      '${episode.episodeNumber}'.padLeft(2, '0'),
    );

/// One wanted item. While selecting it is a checkbox; otherwise it opens the
/// item and has a button that searches for it.
class WantedTile extends StatelessWidget {
  const WantedTile({
    required this.item,
    required this.kind,
    required this.selected,
    required this.canSearch,
    required this.onToggle,
    required this.onOpen,
    required this.onSearch,
    super.key,
  });

  final LibraryItem item;
  final WantedKind kind;

  /// Null while not selecting.
  final bool? selected;

  /// Whether the item can be searched for at all.
  final bool canSearch;

  /// Selects or deselects.
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  /// Null while a search cannot be sent now.
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final title = Text(_title(strings, item));
    final subtitle = _Details(item: item, kind: kind);
    if (selected case final selected?) {
      return CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: selected,
        onChanged: canSearch ? (_) => onToggle() : null,
        title: title,
        subtitle: subtitle,
      );
    }
    return ListTile(
      title: title,
      subtitle: subtitle,
      onTap: onOpen,
      onLongPress: canSearch ? onToggle : null,
      trailing: canSearch
          ? IconButton(
              icon: const Icon(Icons.search),
              tooltip: strings.wantedSearchItem(wantedItemName(strings, item)),
              onPressed: onSearch,
            )
          : null,
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.item, required this.kind});

  final LibraryItem item;
  final WantedKind kind;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final item = this.item;
    final quality = switch (item) {
      Movie(:final file) || Episode(:final file) => file?.quality?.name,
      _ => null,
    };
    final lines = [
      if (item is Episode) ...[
        [
          _number(strings, item),
          if (item.title.isNotEmpty) item.title,
        ].join(' · '),
        if (item.airDateUtc case final aired?)
          strings.wantedAired(formatDay(context, aired)),
      ] else ...[
        ?item.parentTitle,
        if (item.year case final year?) '$year',
      ],
      if (kind == WantedKind.cutoffUnmet) ?quality,
    ];
    // What every item of the list is goes without saying.
    final expected = switch (kind) {
      WantedKind.missing => ItemState.missing,
      WantedKind.cutoffUnmet => ItemState.downloaded,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) Text(line),
        if (item.state != expected)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  item.state.icon,
                  // As large as the text beside it.
                  size: MediaQuery.textScalerOf(context).scale(16),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(item.state.label(strings))),
            ],
          ),
      ],
    );
  }
}
