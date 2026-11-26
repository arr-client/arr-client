/// Hardware-backed or OS-provided secure storage, implemented by the app.
///
/// An instance's credential is stored under `cred/<instanceId>`.
///
/// A value the platform can no longer decrypt is lost and reads as null, so
/// treat null as "ask the user again". Other storage failures are thrown.
abstract interface class SecretStore {
  /// Null if nothing is stored under [key].
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any.
  Future<void> write(String key, String value);

  /// Does nothing if nothing is stored under [key].
  Future<void> delete(String key);
}
