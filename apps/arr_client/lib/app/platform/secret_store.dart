import 'package:core/core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [SecretStore] whose values are encrypted with a key that is itself wrapped
/// by an Android Keystore key, hardware-backed where the device offers that.
final class KeystoreSecretStore implements SecretStore {
  /// Creates a [KeystoreSecretStore].
  const KeystoreSecretStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // Without this, a lost or broken Keystore key makes every later call
      // fail, writes included, until the app's data is cleared. With it, what
      // cannot be read is erased and the user can enter it again.
      resetOnError: true,
      // No biometric prompt: background checks read secrets with no UI.
      enforceBiometrics: false,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
