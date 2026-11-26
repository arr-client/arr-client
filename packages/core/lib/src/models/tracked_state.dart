/// How far the server is with handling a download.
enum TrackedState {
  /// Still downloading.
  downloading,

  /// Waiting to be imported.
  importPending,

  /// Cannot be imported without help.
  importBlocked,

  /// Being imported.
  importing,

  /// Imported.
  imported,

  /// About to be marked as failed.
  failedPending,

  /// Marked as failed.
  failed,

  /// Ignored by the server.
  ignored,

  /// A state the app does not know.
  unknown,
}
