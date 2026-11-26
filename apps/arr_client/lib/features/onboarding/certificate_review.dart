/// Where the certificate screens (T046) plug into the add and edit form.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// What the user decided to trust for one instance.
final class CertificateTrust {
  const CertificateTrust({this.certPin, this.customCa});

  /// An accepted leaf certificate, as `CertificateInfo.sha256`.
  final String? certPin;

  /// A private certificate authority, PEM.
  final String? customCa;
}

/// Shows the certificate that [url] presented, which [failure] carries as a
/// [CertificateUntrusted] or [CertificateChanged]. Answers what to trust, or
/// null to trust nothing. The form then tests again with the answer, and saves
/// it with the instance. A null `customCa` keeps the authority there is.
typedef CertificateReview = Future<CertificateTrust?> Function(
  BuildContext context, {
  required Uri url,
  required ServiceFailure failure,
});

/// Null until there is a screen for it; the form then says it cannot review.
final certificateReviewProvider = Provider<CertificateReview?>((ref) => null);
