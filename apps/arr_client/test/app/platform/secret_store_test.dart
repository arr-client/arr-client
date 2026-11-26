import 'package:arr_client/app/platform/secret_store.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The channel to the plugin's Android side, answered here by [_FakePlugin].
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _FakePlugin {
  final values = <String, String>{};
  final calls = <MethodCall>[];
  PlatformException? failure;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (failure case final failure?) throw failure;
    final arguments = call.arguments as Map<Object?, Object?>;
    final key = arguments['key']! as String;
    switch (call.method) {
      case 'read':
        return values[key];
      case 'write':
        values[key] = arguments['value']! as String;
      case 'delete':
        values.remove(key);
      default:
        throw MissingPluginException(call.method);
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'cred/0b6f2f0e-5d0a-4c55-9d43-0c4c9a3b8e11';
  const SecretStore store = KeystoreSecretStore();
  late _FakePlugin plugin;

  void handleWith(Future<Object?> Function(MethodCall)? handler) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, handler);

  setUp(() {
    plugin = _FakePlugin();
    handleWith(plugin.handle);
  });

  tearDown(() => handleWith(null));

  test('reads null when nothing is stored', () async {
    expect(await store.read(key), isNull);
  });

  test('reads what was written, under the key as given', () async {
    await store.write(key, '{"apiKey":"abc"}');

    expect(await store.read(key), '{"apiKey":"abc"}');
    expect(plugin.values.keys, [key]);
  });

  test('write replaces the stored value', () async {
    await store.write(key, 'old');
    await store.write(key, 'new');

    expect(await store.read(key), 'new');
  });

  test('delete removes only the given key', () async {
    await store.write(key, 'first');
    await store.write('cred/other', 'second');

    await store.delete(key);

    expect(await store.read(key), isNull);
    expect(await store.read('cred/other'), 'second');
  });

  test('delete does nothing when nothing is stored', () async {
    await expectLater(store.delete(key), completes);
  });

  test('every call asks for self-healing storage without biometrics', () async {
    await store.write(key, 'value');
    await store.read(key);
    await store.delete(key);

    expect(plugin.calls, hasLength(3));
    for (final call in plugin.calls) {
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(
        arguments['options'],
        allOf(
          containsPair('resetOnError', 'true'),
          containsPair('enforceBiometrics', 'false'),
          containsPair(
            'keyCipherAlgorithm',
            'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
          ),
          containsPair('storageCipherAlgorithm', 'AES_GCM_NoPadding'),
        ),
      );
    }
  });

  test('platform failures reach the caller', () async {
    plugin.failure = PlatformException(code: 'Exception encountered');
    final failure = throwsA(isA<PlatformException>());

    await expectLater(store.read(key), failure);
    await expectLater(store.write(key, 'value'), failure);
    await expectLater(store.delete(key), failure);
  });
}
