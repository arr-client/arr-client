import 'dart:async';

import 'package:arr_client/app/platform/connectivity.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlugin implements Connectivity {
  List<ConnectivityResult> results = [ConnectivityResult.none];
  PlatformException? error;
  final events = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (error case final thrown?) throw thrown;
    return results;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => events.stream;

  Future<void> dispose() => events.close();
}

void main() {
  late FakePlugin plugin;
  late DeviceNetworkConnectivity connectivity;

  setUp(() {
    plugin = FakePlugin();
    connectivity = DeviceNetworkConnectivity(plugin);
    addTearDown(plugin.dispose);
  });

  Future<Set<NetworkTransport>> transportsFor(
    List<ConnectivityResult> results,
  ) async {
    plugin.results = results;
    return (await connectivity.current()).transports;
  }

  group('current', () {
    const mapping = {
      ConnectivityResult.wifi: {NetworkTransport.wifi},
      ConnectivityResult.ethernet: {NetworkTransport.ethernet},
      ConnectivityResult.mobile: {NetworkTransport.cellular},
      ConnectivityResult.vpn: {NetworkTransport.vpn},
      ConnectivityResult.bluetooth: {NetworkTransport.other},
      ConnectivityResult.satellite: {NetworkTransport.other},
      ConnectivityResult.other: {NetworkTransport.other},
      ConnectivityResult.none: <NetworkTransport>{},
    };

    for (final result in ConnectivityResult.values) {
      test('maps ${result.name}', () async {
        expect(await transportsFor([result]), mapping[result]);
      });
    }

    test('keeps every transport of a VPN over Wi-Fi', () async {
      expect(
        await transportsFor([ConnectivityResult.wifi, ConnectivityResult.vpn]),
        {NetworkTransport.wifi, NetworkTransport.vpn},
      );
    });

    test('treats no results as offline', () async {
      expect(await transportsFor([]), isEmpty);
    });

    test('gives a set that cannot be changed', () async {
      final transports = await transportsFor([ConnectivityResult.wifi]);

      expect(
        () => transports.add(NetworkTransport.vpn),
        throwsUnsupportedError,
      );
    });

    test('lets a platform error surface', () async {
      plugin.error = PlatformException(code: 'unavailable');

      await expectLater(
        connectivity.current(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('changes', () {
    late List<Set<NetworkTransport>> seen;

    setUp(() {
      seen = [];
      final subscription = connectivity.changes.listen(
        (status) => seen.add(status.transports),
      );
      addTearDown(subscription.cancel);
    });

    Future<void> emit(List<ConnectivityResult> results) async {
      plugin.events.add(results);
      await pumpEventQueue();
    }

    test('emits each new network, including going offline', () async {
      await emit([ConnectivityResult.wifi]);
      await emit([ConnectivityResult.none]);
      await emit([ConnectivityResult.mobile]);
      await emit([ConnectivityResult.wifi]);

      expect(seen, [
        {NetworkTransport.wifi},
        <NetworkTransport>{},
        {NetworkTransport.cellular},
        {NetworkTransport.wifi},
      ]);
    });

    test('is quiet when the transports stay the same', () async {
      await emit([ConnectivityResult.wifi, ConnectivityResult.vpn]);
      await emit([ConnectivityResult.vpn, ConnectivityResult.wifi]);
      await emit([ConnectivityResult.bluetooth]);
      await emit([ConnectivityResult.other]);

      expect(seen, [
        {NetworkTransport.wifi, NetworkTransport.vpn},
        {NetworkTransport.other},
      ]);
    });
  });

  test('reads the platform channel by default', () async {
    final messenger =
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
    const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'check' ? ['ethernet', 'vpn'] : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final status = await DeviceNetworkConnectivity().current();

    expect(status.transports, {
      NetworkTransport.ethernet,
      NetworkTransport.vpn,
    });
  });
}
