/// A place on a module-owned screen, returned by capabilities so the app can
/// open it without knowing the module or its paths.
final class ModuleRoute {
  const ModuleRoute({
    required this.instanceId,
    required this.path,
    this.query = const {},
  });

  final String instanceId;

  /// A `ModuleScreen.path` with its parameters filled in.
  final String path;

  final Map<String, String> query;

  /// The location for the router, under `/instances/:instanceId/`.
  String get location => Uri(
    path: '/instances/$instanceId/$path',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}
