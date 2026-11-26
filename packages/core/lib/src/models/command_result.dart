/// How a server task ended.
enum CommandResult {
  /// Did what was asked.
  successful,

  /// Ran but did not succeed.
  unsuccessful,

  /// The server cannot tell.
  indeterminate,

  /// The server says it does not know, or a value the app does not know. A
  /// result the server does not report is null instead.
  unknown,
}
