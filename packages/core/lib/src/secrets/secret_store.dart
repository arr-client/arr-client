/// Hardware-backed or OS-provided secure storage, implemented by the app.
///
/// An instance's credential is stored under `cred/<instanceId>`.
///
/// The platform may erase what it can no longer decrypt, which then reads as
/// null, so treat null as "ask the user again". [read], [write] and [delete]
/// can also throw, even on every call, and callers must handle that.
abstract interface class SecretStore {
  /// Null if nothing is stored under [key].
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any. A failed write may leave nothing
  /// stored, the previous value included.
  Future<void> write(String key, String value);

  /// Does nothing if nothing is stored under [key].
  Future<void> delete(String key);
}
