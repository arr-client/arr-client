/// Hardware-backed or OS-provided secure storage, implemented by the app.
///
/// An instance's credential is stored under `cred/<instanceId>`.
abstract interface class SecretStore {
  /// Null if nothing is stored under [key].
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  /// Does nothing if nothing is stored under [key].
  Future<void> delete(String key);
}
