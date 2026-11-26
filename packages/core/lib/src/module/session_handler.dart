import '../instances/auth_kind.dart';
import '../instances/credential.dart';
import '../network/service_http_client.dart';
import '../network/service_response.dart';
import 'service_result.dart';

/// What a module supplies so the core can keep a session for it. Used only for
/// [AuthKind.userPassword] and [AuthKind.mediaServerAccount].
abstract interface class SessionHandler {
  /// Signs in over [http], which carries no session, and returns the `Cookie`
  /// header value to keep. A rejected login is an [AuthFailed] failure, which
  /// stops further automatic attempts.
  ServiceResult<String> login({
    required AuthKind authKind,
    required Credential credential,
    required ServiceHttpClient http,
  });

  /// Whether [response] means the session is no longer accepted.
  bool isSessionExpired(ServiceResponse response);
}
