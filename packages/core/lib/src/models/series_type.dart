/// How a series numbers its episodes.
enum SeriesType {
  /// Numbered by season and episode.
  standard,

  /// Numbered by date.
  daily,

  /// Absolute numbering.
  anime,

  /// A type the app does not know.
  unknown,
}
