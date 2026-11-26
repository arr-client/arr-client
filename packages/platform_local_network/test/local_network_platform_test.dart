import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_local_network/platform_local_network.dart';

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const channel = MethodChannel('io.github.arrclient/local_network');
  const platform = LocalNetworkPlatform();

  void answer(Map<String, Object?> answers) {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => answers[call.method],
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  test('reads a system that does not enforce the permission', () async {
    answer({
      'snapshot': {'enforced': false},
    });

    final snapshot = await platform.snapshot();

    expect(snapshot.enforced, isFalse);
  });

  test('reads the permission and routes', () async {
    answer({
      'snapshot': {
        'enforced': true,
        'granted': false,
        'lanRoutes': [
          {
            'address': Uint8List.fromList([192, 168, 1, 0]),
            'prefixLength': 24,
            'excluded': false,
          },
        ],
        'vpnRoutes': [
          {
            'address': Uint8List.fromList([10, 0, 0, 0]),
            'prefixLength': 8,
            'excluded': true,
          },
        ],
      },
    });

    final snapshot = await platform.snapshot();

    expect(snapshot.enforced, isTrue);
    expect(snapshot.granted, isFalse);
    expect(snapshot.lanRoutes!.single.address, [192, 168, 1, 0]);
    expect(snapshot.lanRoutes!.single.prefixLength, 24);
    expect(snapshot.lanRoutes!.single.excluded, isFalse);
    expect(snapshot.vpnRoutes.single.excluded, isTrue);
  });

  test('reads the absence of Wi-Fi and Ethernet', () async {
    answer({
      'snapshot': {
        'enforced': true,
        'granted': true,
        'lanRoutes': null,
        'vpnRoutes': <Object?>[],
      },
    });

    final snapshot = await platform.snapshot();

    expect(snapshot.lanRoutes, isNull);
    expect(snapshot.vpnRoutes, isEmpty);
  });

  test('answers whether a request was granted', () async {
    answer({'requestPermission': true});

    expect(await platform.requestPermission(), isTrue);
  });
}
