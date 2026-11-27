import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../lidarr_routes.dart';
import 'album_detail.dart';
import 'artist_detail.dart';
import 'lidarr_sources.dart';

/// The module's screens, which read what [sourcesOf] gives for an instance.
List<ModuleScreen> lidarrScreens(
  LidarrSources Function(InstanceContext instance) sourcesOf,
) {
  // [build] gives null for parameters that are not what the path promises.
  ModuleScreen screen(
    String path,
    Widget? Function(LidarrSources sources, int? Function(String name) number)
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
      artistPath,
      (sources, number) => switch (number('artistId')) {
        final id? => ArtistScreen(sources: sources, artistId: id),
        null => null,
      },
    ),
    screen(
      albumPath,
      (sources, number) => switch (number('albumId')) {
        final id? => AlbumScreen(sources: sources, albumId: id),
        null => null,
      },
    ),
  ];
}
