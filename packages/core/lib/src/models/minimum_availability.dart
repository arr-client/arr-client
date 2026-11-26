/// When a movie counts as available to search for.
enum MinimumAvailability {
  /// To be announced.
  tba,

  /// Once announced.
  announced,

  /// Once in cinemas.
  inCinemas,

  /// Once released.
  released,

  /// A value the app does not know.
  unknown,
}
