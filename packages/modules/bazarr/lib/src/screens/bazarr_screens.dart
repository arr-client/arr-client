import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../subtitles_route.dart';
import 'bazarr_source.dart';
import 'subtitle_search_screen.dart';
import 'subtitle_series_screen.dart';
import 'subtitle_title_screen.dart';
import 'subtitles_screen.dart';

typedef _Number = int? Function(String parameter);

SubtitleMedia? _movie(_Number number) => switch (number('radarrId')) {
  final id? => SubtitleMedia.movie(id),
  null => null,
};

SubtitleMedia? _episode(_Number number) =>
    switch ((number('seriesId'), number('episodeId'))) {
      (final seriesId?, final episodeId?) => SubtitleMedia.episode(
        seriesId: seriesId,
        episodeId: episodeId,
      ),
      _ => null,
    };

/// The module's screens, which read what [sourceOf] gives for an instance.
List<ModuleScreen> bazarrScreens(
  BazarrSource Function(InstanceContext instance) sourceOf,
) {
  // [build] gives null for parameters that are not what the path promises.
  ModuleScreen screen(
    String path,
    Widget? Function(BazarrSource source, String name, _Number number) build,
  ) => ModuleScreen(
    path: path,
    builder: (context, instance, parameters) =>
        build(
          sourceOf(instance),
          instance.instance.name,
          (parameter) => int.tryParse(parameters[parameter] ?? ''),
        ) ??
        Scaffold(appBar: AppBar(), body: ItemGoneView()),
  );

  ModuleScreen title(String path, SubtitleMedia? Function(_Number) media) =>
      screen(
        path,
        (source, name, number) => switch (media(number)) {
          final media? => SubtitleTitleScreen(
            target: (source: source, media: media),
            name: name,
          ),
          null => null,
        },
      );

  ModuleScreen search(String path, SubtitleMedia? Function(_Number) media) =>
      screen(
        path,
        (source, name, number) => switch (media(number)) {
          final media? => SubtitleSearchScreen(
            target: (source: source, media: media),
            name: name,
          ),
          null => null,
        },
      );

  return [
    screen(
      subtitlesPattern,
      (source, name, number) => SubtitlesScreen(source: source, name: name),
    ),
    title(moviePattern, _movie),
    search(movieSearchPattern, _movie),
    screen(
      seriesPattern,
      (source, name, number) => switch (number('seriesId')) {
        final id? => SubtitleSeriesScreen(
          target: (source: source, media: SubtitleMedia.series(id)),
        ),
        null => null,
      },
    ),
    title(episodePattern, _episode),
    search(episodeSearchPattern, _episode),
  ];
}
