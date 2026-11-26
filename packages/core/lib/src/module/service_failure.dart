import '../network/certificate_info.dart';
import 'localized_text.dart';

/// Why an operation against a service failed.
///
/// Failures carry no tokens, headers, cookies or URLs.
sealed class ServiceFailure {
  const ServiceFailure();
}

/// No answer from the address.
final class Unreachable extends ServiceFailure {
  const Unreachable();
}

/// The host name could not be resolved.
final class DnsFailure extends ServiceFailure {
  const DnsFailure();
}

/// The server's certificate is not trusted. Nothing was sent.
final class CertificateUntrusted extends ServiceFailure {
  const CertificateUntrusted(this.certificate);

  /// What the server presented, for the user to review.
  final CertificateInfo certificate;
}

/// The server's certificate differs from the accepted one. Nothing was sent.
final class CertificateChanged extends ServiceFailure {
  const CertificateChanged(this.certificate);

  /// What the server presented now.
  final CertificateInfo certificate;
}

/// The token or login was rejected.
final class AuthFailed extends ServiceFailure {
  const AuthFailed({this.hint});

  /// A possible cause the module wants shown, where the server does not say.
  final LocalizedText? hint;
}

/// The server accepted the identity but refused this to it.
final class Forbidden extends ServiceFailure {
  const Forbidden();
}

/// The address answers, but it is not the expected service.
final class WrongService extends ServiceFailure {
  const WrongService();
}

/// A proxy answered with a web page, typically a login page, instead of data.
final class ProxyInterception extends ServiceFailure {
  const ProxyInterception();
}

/// The server redirected somewhere credentials are not sent.
final class Redirected extends ServiceFailure {
  const Redirected({this.host});

  /// The target host only; never the full address.
  final String? host;
}

/// The server refused the host name used to reach it.
final class HostRejected extends ServiceFailure {
  const HostRejected();
}

/// The server is older than the minimum supported version.
final class UnsupportedVersion extends ServiceFailure {
  const UnsupportedVersion({this.version});

  /// The version the server reported.
  final String? version;
}

/// The server answers reads but rejects writes.
final class WritesRefused extends ServiceFailure {
  const WritesRefused();
}

/// The operating system's local network permission is missing. A refusal by
/// the server is [Forbidden].
final class PermissionDenied extends ServiceFailure {
  const PermissionDenied();
}

/// The item no longer exists.
final class NotFound extends ServiceFailure {
  const NotFound();
}

/// The change clashes with the server's state, for example it already exists.
final class Conflict extends ServiceFailure {
  const Conflict();
}

/// The server rejected the values sent.
final class Validation extends ServiceFailure {
  const Validation(this.messages);

  /// The server's own messages.
  final List<String> messages;
}

/// The server failed.
final class ServerError extends ServiceFailure {
  const ServerError({this.statusCode});

  final int? statusCode;
}

/// The response could not be understood.
final class MalformedResponse extends ServiceFailure {
  const MalformedResponse();
}

/// A change may or may not have reached the server. It is not sent again.
final class OutcomeUnknown extends ServiceFailure {
  const OutcomeUnknown();
}
