/// A certificate that is not trusted and that nothing was accepted before
/// (spec story 1, scenario 3).
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'certificate_widgets.dart';
import 'trust_decision.dart';

/// Shows the fingerprint of [certificate], to accept it or not.
class FingerprintReviewScreen extends StatelessWidget {
  const FingerprintReviewScreen({
    required this.url,
    required this.certificate,
    this.hasCustomCa = false,
    super.key,
  });

  final Uri url;
  final CertificateInfo certificate;

  /// An imported authority did not vouch for the certificate.
  final bool hasCustomCa;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return CertificatePage(
      title: strings.certificateReviewTitle,
      children: [
        Text(
          strings.certificateUntrustedBy(url.authority),
          style: theme.textTheme.bodyLarge,
        ),
        if (hasCustomCa) ...[
          const SizedBox(height: 12),
          CertificateWarning(strings.certificateAuthorityNotEnough),
        ],
        const SizedBox(height: 24),
        Fingerprint(
          label: strings.certificateFingerprint,
          sha256: certificate.sha256,
        ),
        const SizedBox(height: 8),
        Text(strings.certificateCompare),
        const SizedBox(height: 24),
        CertificateDetails(certificate),
        const SizedBox(height: 12),
        Text(strings.certificatePinMeaning),
        const SizedBox(height: 16),
        TrustDecision(
          statement: strings.certificateChecked,
          accept: strings.certificateTrust,
          refuse: strings.certificateDoNotTrust,
          url: url,
          sha256: certificate.sha256,
        ),
      ],
    );
  }
}
