import 'package:flutter/services.dart';

import 'local_network_snapshot.dart';
import 'network_route.dart';

/// The Android side of the local network permission.
///
/// It works in any isolate whose Flutter engine registers plugins, background
/// ones included. Android only: elsewhere its calls throw
/// [MissingPluginException].
class LocalNetworkPlatform {
  /// Creates a [LocalNetworkPlatform].
  const LocalNetworkPlatform();

  static const _channel = MethodChannel('io.github.arrclient/local_network');

  /// Reads the permission and the networks. Never prompts.
  Future<LocalNetworkSnapshot> snapshot() async {
    final values = (await _channel.invokeMapMethod<String, Object?>(
      'snapshot',
    ))!;
    if (values['enforced'] == false) {
      return const LocalNetworkSnapshot.notEnforced();
    }
    return LocalNetworkSnapshot(
      granted: values['granted']! as bool,
      lanRoutes: switch (values['lanRoutes']) {
        final List<Object?> routes => _routes(routes),
        _ => null,
      },
      vpnRoutes: _routes(values['vpnRoutes']! as List<Object?>),
    );
  }

  /// Shows the system prompt and answers whether the permission is then held.
  ///
  /// In an isolate without an activity, as in the background, nothing is shown.
  Future<bool> requestPermission() async =>
      (await _channel.invokeMethod<bool>('requestPermission'))!;

  static List<NetworkRoute> _routes(List<Object?> values) => [
    for (final route in values.cast<Map<Object?, Object?>>())
      NetworkRoute(
        route['address']! as Uint8List,
        route['prefixLength']! as int,
        excluded: route['excluded']! as bool,
      ),
  ];
}
