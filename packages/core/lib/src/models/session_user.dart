import 'quota.dart';
import 'service_permission.dart';

/// The signed-in user of a request service.
final class SessionUser {
  const SessionUser({
    required this.id,
    required this.name,
    required this.permissions,
    this.quota,
  });

  final int id;

  final String name;

  final Set<ServicePermission> permissions;

  final Quota? quota;
}
