/// The leaf certificate a server presented.
final class CertificateInfo {
  /// Creates a [CertificateInfo].
  const CertificateInfo({
    required this.sha256,
    this.subject,
    this.issuer,
    this.notBefore,
    this.notAfter,
  });

  /// The fingerprint, as stored in `Instance.certPin`: 64 lower-case hex digits.
  final String sha256;

  /// Whom the certificate names.
  final String? subject;

  /// Who signed it.
  final String? issuer;

  /// Start of validity.
  final DateTime? notBefore;

  /// End of validity.
  final DateTime? notAfter;
}
