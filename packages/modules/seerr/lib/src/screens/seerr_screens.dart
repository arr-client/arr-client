import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../routes.dart';
import 'discover_screen.dart';
import 'quota_screen.dart';
import 'request_screen.dart';
import 'seerr_source.dart';
import 'title_screen.dart';

const _requestPermissions = {
  ServicePermission.requestMovies,
  ServicePermission.requestSeries,
  ServicePermission.request4kMovies,
  ServicePermission.request4kSeries,
};

/// The module's screens, which read what [sourceOf] gives for an instance.
List<ModuleScreen> seerrScreens(
  SeerrSource Function(InstanceContext instance) sourceOf,
) {
  // The title that the path names, or null if it names none.
  DiscoveryRef? titleOf(Map<String, String> parameters) {
    final type = DiscoveryMediaType.values.asNameMap()[parameters['mediaType']];
    final id = int.tryParse(parameters['tmdbId'] ?? '');
    return type == null || id == null
        ? null
        : DiscoveryRef(mediaType: type, tmdbId: id);
  }

  Widget gone() => Scaffold(appBar: AppBar(), body: ItemGoneView());

  return [
    ModuleScreen(
      path: discoverPattern,
      builder: (context, instance, parameters) {
        final probed = instance.instance.lastProbe?.permissions;
        return DiscoverScreen(
          source: sourceOf(instance),
          name: instance.instance.name,
          offersQuota:
              probed == null || probed.any(_requestPermissions.contains),
        );
      },
    ),
    ModuleScreen(
      path: titlePattern,
      builder: (context, instance, parameters) => switch (titleOf(parameters)) {
        // Another title at the same path starts over.
        final wanted? => TitleScreen(
          key: ValueKey(wanted),
          source: sourceOf(instance),
          wanted: wanted,
        ),
        null => gone(),
      },
    ),
    ModuleScreen(
      path: requestPattern,
      builder: (context, instance, parameters) => switch ((
        titleOf(parameters),
        bool.tryParse(parameters['is4k'] ?? ''),
      )) {
        (final wanted?, final is4k?) => RequestScreen(
          key: ValueKey((wanted, is4k)),
          source: sourceOf(instance),
          wanted: wanted,
          is4k: is4k,
        ),
        _ => gone(),
      },
    ),
    ModuleScreen(
      path: quotaPattern,
      builder: (context, instance, parameters) =>
          QuotaScreen(source: sourceOf(instance)),
    ),
  ];
}
