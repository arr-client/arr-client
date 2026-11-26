/// The leaf certificate a server presented.
final class CertificateInfo {
  const CertificateInfo({
    required this.sha256,
    this.subject,
    this.issuer,
    this.notBefore,
    this.notAfter,
  });

  /// The fingerprint, as stored in `Instance.certPin`: 64 lower-case hex digits.
  final String sha256;

  final String? subject;

  final String? issuer;

  final DateTime? notBefore;

  final DateTime? notAfter;
}
