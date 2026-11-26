/// A user of a request service.
final class ServiceUser {
  /// Creates a [ServiceUser].
  const ServiceUser({required this.id, required this.name});

  /// The server's id of the user.
  final int id;

  /// Name to show.
  final String name;
}
