/// What the user can be notified of (data-model.md
/// NotificationSubscription.eventType). Names are persisted.
enum NotificationEventType {
  /// An item was imported.
  imported,

  /// A download failed or needs attention.
  downloadProblem,

  /// A health problem is new or has worsened.
  healthIssue,

  /// A request is waiting for approval.
  pendingRequest,

  /// One of the user's own requests was approved or declined, or what it asked
  /// for became available.
  ownRequestUpdate,
}
