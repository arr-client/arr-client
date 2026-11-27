import 'package:material_ui/material_ui.dart';

import '../l10n/generated/bazarr_localizations.dart';
import 'bazarr_source.dart';
import 'subtitle_tabs.dart';

/// Wanted subtitles, history and titles of one instance: spec story 10.
///
/// It must be below a Riverpod `ProviderScope`, and its rows open routes of the
/// module.
class SubtitlesScreen extends StatelessWidget {
  /// Creates the screen of [source], for the instance called [name].
  const SubtitlesScreen({required this.source, required this.name, super.key});

  /// Where it reads from.
  final BazarrSource source;

  /// The instance's name.
  final String name;

  @override
  Widget build(BuildContext context) {
    final strings = BazarrLocalizations.of(context);
    return DefaultTabController(
      length: SubtitleTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          bottom: TabBar(
            tabs: [
              for (final tab in SubtitleTab.values)
                Tab(
                  text: switch (tab) {
                    SubtitleTab.wanted => strings.wantedTab,
                    SubtitleTab.history => strings.historyTab,
                    SubtitleTab.browse => strings.browseTab,
                  },
                ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(
            children: [
              for (final tab in SubtitleTab.values)
                SubtitleTabView(source: source, tab: tab),
            ],
          ),
        ),
      ),
    );
  }
}
