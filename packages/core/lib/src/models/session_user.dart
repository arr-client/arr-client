import 'quota.dart';
import 'service_permission.dart';

/// The signed-in user of a request service.
final class SessionUser {
  /// Creates a [SessionUser].
  const SessionUser({
    required this.id,
    required this.name,
    required this.permissions,
    this.quota,
  });

  /// The server's id of the user.
  final int id;

  /// Name to show.
  final String name;

  /// What the user may do.
  final Set<ServicePermission> permissions;

  /// What the user may still request.
  final Quota? quota;
}
