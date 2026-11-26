/// Where a request is.
enum RequestStatus {
  /// Waiting for approval.
  pending,

  /// Approved.
  approved,

  /// Declined.
  declined,

  /// Failed.
  failed,

  /// Done.
  completed,

  /// A status the app does not know.
  unknown,
}
