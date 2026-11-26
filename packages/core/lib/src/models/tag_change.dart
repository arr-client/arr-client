/// How a bulk edit applies its tags.
enum TagChange {
  /// Add the tags.
  add,

  /// Remove the tags.
  remove,

  /// Replace all tags with these.
  replace,
}
