/// How serious a health issue is.
enum HealthLevel {
  /// Worth knowing.
  notice,

  /// Something may not work.
  warning,

  /// Something does not work.
  error,

  /// A level the app does not know.
  unknown,
}
