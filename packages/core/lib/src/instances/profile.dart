/// A named set of instances, for example "Home" and "Away".
final class Profile {
  /// Creates a [Profile].
  const Profile({required this.id, required this.name, this.sortOrder = 0});

  /// A UUID, never changed.
  final String id;

  /// The user's name for the profile.
  final String name;

  /// Position among the profiles.
  final int sortOrder;
}
