/// What a server task's status and result amount to.
enum CommandOutcome {
  /// Not finished yet.
  pending,

  /// Did what was asked.
  succeeded,

  /// Did not do what was asked.
  failed,

  /// No longer followed, and the server does not tell which.
  unknown,
}
