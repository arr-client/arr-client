import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../sonarr_routes.dart';
import 'episode_detail.dart';
import 'season_detail.dart';
import 'series_detail.dart';
import 'sonarr_sources.dart';

/// The module's screens, which read what [sourcesOf] gives for an instance.
List<ModuleScreen> sonarrScreens(
  SonarrSources Function(InstanceContext instance) sourcesOf,
) {
  // [build] gives null for parameters that are not what the path promises.
  ModuleScreen screen(
    String path,
    Widget? Function(SonarrSources sources, int? Function(String name) number)
    build,
  ) => ModuleScreen(
    path: path,
    builder: (context, instance, parameters) =>
        build(
          sourcesOf(instance),
          (name) => int.tryParse(parameters[name] ?? ''),
        ) ??
        Scaffold(appBar: AppBar(), body: ItemGoneView()),
  );

  return [
    screen(
      seriesPath,
      (sources, number) => switch (number('seriesId')) {
        final id? => SeriesDetailScreen(sources: sources, seriesId: id),
        null => null,
      },
    ),
    screen(
      seasonPath,
      (sources, number) => switch ((number('seriesId'), number('season'))) {
        (final id?, final season?) => SeasonScreen(
          sources: sources,
          seriesId: id,
          number: season,
        ),
        _ => null,
      },
    ),
    screen(
      episodePath,
      (sources, number) => switch (number('episodeId')) {
        final id? => EpisodeScreen(sources: sources, episodeId: id),
        null => null,
      },
    ),
  ];
}
