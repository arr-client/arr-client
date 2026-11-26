/// Opening the screen that fits why a certificate was refused.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../certificate_review.dart';
import 'certificate_changed_screen.dart';
import 'fingerprint_review_screen.dart';

/// The app's [CertificateReview]. A certificate seen for the first time and one
/// that replaces an accepted one have screens of their own, so that the second
/// is not taken for the first. Leaving either one trusts nothing.
Future<CertificateTrust?> showCertificateReview(
  BuildContext context, {
  required Uri url,
  required ServiceFailure failure,
  required String? pinned,
  required bool hasCustomCa,
}) {
  final Widget screen = switch (failure) {
    CertificateUntrusted(:final certificate) => FingerprintReviewScreen(
      url: url,
      certificate: certificate,
      hasCustomCa: hasCustomCa,
    ),
    CertificateChanged(:final certificate) => CertificateChangedScreen(
      url: url,
      certificate: certificate,
      pinned: pinned,
    ),
    _ => throw ArgumentError.value(failure, 'failure', 'not a certificate'),
  };
  return Navigator.of(context)
      .push(MaterialPageRoute<CertificateTrust>(builder: (context) => screen));
}
