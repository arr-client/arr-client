import '../instances/auth_kind.dart';
import '../instances/credential.dart';

/// Where one request goes, with which credential and under which trust. Holds
/// secrets: never log it.
final class ConnectionSettings {
  /// Creates a [ConnectionSettings].
  const ConnectionSettings({
    required this.url,
    required this.authKind,
    this.credential = const Credential(),
    this.certPin,
    this.customCa,
  });

  /// The instance's address: http or https, maybe with a sub-path.
  final Uri url;

  /// How the instance authenticates.
  final AuthKind authKind;

  /// The instance's secrets. They are sent to [url]'s origin only.
  final Credential credential;

  /// SHA-256 of an accepted leaf certificate, as in `Instance.certPin`.
  final String? certPin;

  /// A private certificate authority for this instance, PEM.
  final String? customCa;
}
