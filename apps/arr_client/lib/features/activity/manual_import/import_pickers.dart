/// The dialogs that correct what a file is. Each returns null if closed without
/// a choice.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'import_labels.dart';

/// Asks for a movie or series.
Future<ItemRef?> pickImportItem(
  BuildContext context, {
  required String title,
  required List<LibraryItem> items,
  ItemRef? current,
}) => showDialog<ItemRef>(
  context: context,
  builder: (_) => _ItemPicker(title: title, items: items, current: current),
);

/// Asks for episodes of one season of [episodes].
Future<List<int>?> pickImportEpisodes(
  BuildContext context, {
  required List<Episode> episodes,
  required List<int> current,
}) => showDialog<List<int>>(
  context: context,
  builder: (_) => _EpisodePicker(episodes: episodes, current: current),
);

Future<Quality?> pickImportQuality(
  BuildContext context, {
  required List<Quality> qualities,
  Quality? current,
}) => showDialog<Quality>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(AppLocalizations.of(context).manualImportChooseQuality),
    children: [
      for (final quality in qualities)
        ListTile(
          title: Text(quality.name),
          selected: quality.id == current?.id,
          trailing: quality.id == current?.id ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, quality),
        ),
    ],
  ),
);

/// Asks for at least one language.
Future<List<Language>?> pickImportLanguages(
  BuildContext context, {
  required List<Language> languages,
  required List<Language> current,
}) => showDialog<List<Language>>(
  context: context,
  builder: (_) => _LanguagePicker(languages: languages, current: current),
);

class _LanguagePicker extends StatefulWidget {
  const _LanguagePicker({required this.languages, required this.current});

  final List<Language> languages;
  final List<Language> current;

  @override
  State<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  late final _chosen = {
    for (final language in widget.current)
      if (widget.languages.any((other) => other.id == language.id)) language.id,
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(strings.manualImportChooseLanguages),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final language in widget.languages)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(language.name),
              value: _chosen.contains(language.id),
              onChanged: (value) => setState(
                () => value ?? false
                    ? _chosen.add(language.id)
                    : _chosen.remove(language.id),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(UiLocalizations.of(context).cancel),
        ),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final language in widget.languages)
                    if (_chosen.contains(language.id)) language,
                ]),
          child: Text(strings.manualImportUse),
        ),
      ],
    );
  }
}

/// A whole-screen dialog with a title and a way out.
class _PickerPage extends StatelessWidget {
  const _PickerPage({required this.title, required this.body, this.action});

  final String title;
  final Widget body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: UiLocalizations.of(context).cancel,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title),
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: switch (action) {
        final action? => SafeArea(
          child: Padding(padding: const EdgeInsets.all(16), child: action),
        ),
        null => null,
      },
    ),
  );
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.title, required this.items, this.current});

  final String title;
  final List<LibraryItem> items;
  final ItemRef? current;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  var _filter = '';

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final wanted = _filter.trim().toLowerCase();
    final shown = [
      for (final item in widget.items)
        if (item.title.toLowerCase().contains(wanted)) item,
    ];
    return _PickerPage(
      title: widget.title,
      // The field scrolls with the titles, so that large text leaves room.
      body: ListView.builder(
        itemCount: shown.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: strings.manualImportFilter,
                    ),
                    onChanged: (value) => setState(() => _filter = value),
                  ),
                ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(strings.manualImportNoMatch),
                    ),
                  ),
              ],
            );
          }
          final item = shown[index - 1];
          final chosen = item.ref == widget.current;
          return ListTile(
            title: Text(importItemLabel(strings, item)),
            selected: chosen,
            trailing: chosen ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, item.ref),
          );
        },
      ),
    );
  }
}

class _EpisodePicker extends StatefulWidget {
  const _EpisodePicker({required this.episodes, required this.current});

  /// In the order of seasons and numbers.
  final List<Episode> episodes;
  final List<int> current;

  @override
  State<_EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<_EpisodePicker> {
  late final _chosen = {
    for (final episode in widget.episodes)
      if (widget.current.contains(episode.ref.remoteId)) episode.ref.remoteId,
  };

  /// The server drops the episodes of a file that has two seasons' of them.
  void _toggle(Episode episode, bool chosen) => setState(() {
    if (!chosen) {
      _chosen.remove(episode.ref.remoteId);
      return;
    }
    _chosen
      ..removeWhere(
        (id) => widget.episodes.any(
          (other) =>
              other.ref.remoteId == id &&
              other.seasonNumber != episode.seasonNumber,
        ),
      )
      ..add(episode.ref.remoteId);
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final episodes = widget.episodes;
    return _PickerPage(
      title: strings.manualImportChooseEpisodes,
      action: FilledButton(
        onPressed: _chosen.isEmpty
            ? null
            : () => Navigator.pop(context, [
                for (final episode in episodes)
                  if (_chosen.contains(episode.ref.remoteId))
                    episode.ref.remoteId,
              ]),
        child: Text(strings.manualImportUse),
      ),
      body: ListView.builder(
        itemCount: episodes.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                episodes.isEmpty
                    ? strings.manualImportNoSeriesEpisodes
                    : strings.manualImportOneSeason,
              ),
            );
          }
          final episode = episodes[index - 1];
          final season = episode.seasonNumber;
          final tile = CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(importEpisodeLabel(strings, episode)),
            value: _chosen.contains(episode.ref.remoteId),
            onChanged: (value) => _toggle(episode, value ?? false),
          );
          if (index > 1 && episodes[index - 2].seasonNumber == season) {
            return tile;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Semantics(
                  header: true,
                  child: Text(
                    importSeasonLabel(strings, season),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
              tile,
            ],
          );
        },
      ),
    );
  }
}
