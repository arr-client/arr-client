import 'service_result.dart';

/// Keeps one instance's session. Implemented by the core around a module's
/// [SessionHandler]: it stores the session in secure storage, and when the
/// session has expired it signs in again and repeats a read once. A write is
/// never repeated. A rejected login sets `Instance.authFailed`, and while that
/// is set no login or authenticated request is made.
abstract interface class SessionAuthenticator {
  /// Signs in with the instance's credential, replacing any session.
  ServiceResult<void> login();
}
