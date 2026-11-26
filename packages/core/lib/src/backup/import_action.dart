/// What an import does with one record. Records match on id.
enum ImportAction {
  /// The id is new here.
  add,

  /// The record with the id is replaced.
  replace,
}
