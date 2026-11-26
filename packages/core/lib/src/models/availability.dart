/// Whether a title is on the server, for one variant.
enum Availability {
  /// Not known to the server, or a value the app does not know.
  unknown,

  /// Waiting for approval.
  pending,

  /// Being fetched.
  processing,

  /// Partly available.
  partial,

  /// Available.
  available,

  /// Blocked on the server.
  blocklisted,

  /// Removed from the server.
  deleted,
}
