import 'package:flutter/widgets.dart';

import 'instance_context.dart';

/// Builds a module screen. [parameters] holds the path and query parameters.
typedef ModuleScreenBuilder = Widget Function(
  BuildContext context,
  InstanceContext instance,
  Map<String, String> parameters,
);

/// A screen a module owns.
final class ModuleScreen {
  const ModuleScreen({required this.path, required this.builder});

  /// A router pattern relative to `/instances/:instanceId/`. It starts with the
  /// module's id so that modules cannot collide, for example
  /// `radarr/movies/:movieId`.
  final String path;

  final ModuleScreenBuilder builder;
}
