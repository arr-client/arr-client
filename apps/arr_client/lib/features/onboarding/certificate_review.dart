/// Where the add and edit form asks what to trust of a certificate.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'certificate/show_certificate_review.dart';

/// What the user decided to trust for one instance.
final class CertificateTrust {
  /// The user accepted the certificate with the fingerprint [certPin], or
  /// keeps it, having accepted it before.
  const CertificateTrust.certificate(String this.certPin) : customCa = null;

  /// The user trusts the authority [customCa], in place of any accepted
  /// certificate of the address.
  const CertificateTrust.authority(String this.customCa) : certPin = null;

  /// An accepted leaf certificate, as `CertificateInfo.sha256`. It keeps the
  /// authority there is.
  final String? certPin;

  /// A private certificate authority, PEM.
  final String? customCa;
}

/// Shows the certificate that [url] presented, which [failure] carries as a
/// [CertificateUntrusted] or [CertificateChanged]. [pinned] is the accepted
/// fingerprint it differs from, and [hasCustomCa] whether an authority was
/// tried and did not vouch for the certificate. Answers what to trust, or null to trust nothing. The form then
/// tests again with the answer, and saves it with the instance.
typedef CertificateReview = Future<CertificateTrust?> Function(
  BuildContext context, {
  required Uri url,
  required ServiceFailure failure,
  required String? pinned,
  required bool hasCustomCa,
});

final certificateReviewProvider = Provider<CertificateReview>(
  (ref) => showCertificateReview,
);
