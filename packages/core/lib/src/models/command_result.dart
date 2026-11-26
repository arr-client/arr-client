/// How a server task ended.
enum CommandResult {
  /// Did what was asked.
  successful,

  /// Ran but did not succeed.
  unsuccessful,

  /// The server cannot tell.
  indeterminate,

  /// Not reported, or a value the app does not know.
  unknown,
}
