/// What happened.
enum HistoryEventType {
  /// A release was sent to a download client.
  grabbed,

  /// Files were imported.
  imported,

  /// A download failed.
  failed,

  /// Files were renamed.
  renamed,

  /// Files were deleted.
  deleted,

  /// Anything else.
  other,
}
