import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/sonarr_localizations.dart';

/// How many of a season's wanted episodes the server has.
class SeasonProgress extends StatelessWidget {
  /// Creates a [SeasonProgress].
  const SeasonProgress({required this.season, super.key});

  /// The season.
  final Season season;

  @override
  Widget build(BuildContext context) {
    final strings = SonarrLocalizations.of(context);
    // The server counts as wanted what is aired and monitored, or present.
    final wanted = season.episodeCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          wanted > 0
              ? strings.episodeProgress(season.episodeFileCount, wanted)
              : strings.episodeTotal(season.totalEpisodeCount),
        ),
        if (wanted > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            // The text above says the same.
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: (season.episodeFileCount / wanted).clamp(0, 1),
              ),
            ),
          ),
        if (!season.monitored) Text(UiLocalizations.of(context).notMonitored),
      ],
    );
  }
}
