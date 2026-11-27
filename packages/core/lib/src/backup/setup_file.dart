/// A setup export that was read and found valid in itself.
abstract interface class SetupFile {
  /// When it was exported. UTC.
  DateTime get createdAt;

  /// Whether it was encrypted, and so may carry credentials.
  bool get includesCredentials;
}
