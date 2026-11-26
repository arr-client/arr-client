/// A library item's state, declared from highest to lowest precedence.
enum ItemState {
  downloading,
  downloaded,
  partial,
  unmonitored,
  unreleased,
  missing,
}
