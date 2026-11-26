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
  /// Creates an [Unreachable].
  const Unreachable();
}

/// The host name could not be resolved.
final class DnsFailure extends ServiceFailure {
  /// Creates a [DnsFailure].
  const DnsFailure();
}

/// The server's certificate is not trusted. Nothing was sent.
final class CertificateUntrusted extends ServiceFailure {
  /// Creates a [CertificateUntrusted].
  const CertificateUntrusted(this.certificate);

  /// What the server presented, for the user to review.
  final CertificateInfo certificate;
}

/// The server's certificate differs from the accepted one. Nothing was sent.
final class CertificateChanged extends ServiceFailure {
  /// Creates a [CertificateChanged].
  const CertificateChanged(this.certificate);

  /// What the server presented now.
  final CertificateInfo certificate;
}

/// The token or login was rejected.
final class AuthFailed extends ServiceFailure {
  /// Creates an [AuthFailed].
  const AuthFailed({this.hint});

  /// A possible cause the module wants shown, where the server does not say.
  final LocalizedText? hint;
}

/// The server accepted the identity but refused this to it.
final class Forbidden extends ServiceFailure {
  /// Creates a [Forbidden].
  const Forbidden();
}

/// The address answers, but it is not the expected service.
final class WrongService extends ServiceFailure {
  /// Creates a [WrongService].
  const WrongService();
}

/// A proxy answered with a web page, typically a login page, instead of data.
final class ProxyInterception extends ServiceFailure {
  /// Creates a [ProxyInterception].
  const ProxyInterception();
}

/// The server redirected somewhere credentials are not sent.
final class Redirected extends ServiceFailure {
  /// Creates a [Redirected].
  const Redirected({this.host});

  /// The target host only; never the full address.
  final String? host;
}

/// The server refused the host name used to reach it.
final class HostRejected extends ServiceFailure {
  /// Creates a [HostRejected].
  const HostRejected();
}

/// The server is older than the minimum supported version.
final class UnsupportedVersion extends ServiceFailure {
  /// Creates an [UnsupportedVersion].
  const UnsupportedVersion({this.version});

  /// The version the server reported.
  final String? version;
}

/// The server answers reads but rejects writes.
final class WritesRefused extends ServiceFailure {
  /// Creates a [WritesRefused].
  const WritesRefused();
}

/// The operating system's local network permission is missing. A refusal by
/// the server is [Forbidden].
final class PermissionDenied extends ServiceFailure {
  /// Creates a [PermissionDenied].
  const PermissionDenied();
}

/// The item no longer exists.
final class NotFound extends ServiceFailure {
  /// Creates a [NotFound].
  const NotFound();
}

/// The change clashes with the server's state, for example it already exists.
final class Conflict extends ServiceFailure {
  /// Creates a [Conflict].
  const Conflict();
}

/// The server rejected the values sent.
final class Validation extends ServiceFailure {
  /// Creates a [Validation].
  const Validation(this.messages);

  /// The server's own messages.
  final List<String> messages;
}

/// The server failed.
final class ServerError extends ServiceFailure {
  /// Creates a [ServerError].
  const ServerError({this.statusCode});

  /// The HTTP status.
  final int? statusCode;
}

/// The response could not be understood.
final class MalformedResponse extends ServiceFailure {
  /// Creates a [MalformedResponse].
  const MalformedResponse();
}

/// A change may or may not have reached the server. It is not sent again.
final class OutcomeUnknown extends ServiceFailure {
  /// Creates an [OutcomeUnknown].
  const OutcomeUnknown();
}
