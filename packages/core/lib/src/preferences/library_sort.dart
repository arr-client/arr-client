/// The order of a library.
final class LibrarySort {
  /// Creates a [LibrarySort].
  const LibrarySort({this.field = title, this.ascending = true});

  /// The [field] that orders by sort title.
  static const title = 'title';

  /// What to order by. The library screen defines the values, and treats one it
  /// does not know as [title].
  final String field;

  /// Whether the smallest or earliest comes first.
  final bool ascending;

  @override
  bool operator ==(Object other) =>
      other is LibrarySort &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}
