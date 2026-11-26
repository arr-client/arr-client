import 'package:core/core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [SecretStore] whose values are encrypted with a key that is itself wrapped
/// by an Android Keystore key, hardware-backed where the device offers that.
///
/// [read], [write] and [delete] can throw, and for some Keystore faults they
/// throw on every call. Callers must handle that.
final class KeystoreSecretStore implements SecretStore {
  /// Creates a [KeystoreSecretStore].
  const KeystoreSecretStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // A key that can no longer unwrap the data is reset, erasing it, and a
      // value that fails to decrypt is erased. Other Keystore faults, such as
      // UnrecoverableKeyException, are thrown with nothing reset.
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
