/// A certificate other than the accepted one (FR-005): it may be a renewal or
/// someone in between, and only the user can tell which.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'certificate_widgets.dart';
import 'trust_decision.dart';

/// Shows that [certificate] differs from the accepted one, with both
/// fingerprints. Keeping the accepted one is the primary choice.
class CertificateChangedScreen extends StatelessWidget {
  const CertificateChangedScreen({
    required this.url,
    required this.certificate,
    required this.pinned,
    super.key,
  });

  final Uri url;
  final CertificateInfo certificate;

  /// The fingerprint that was accepted.
  final String? pinned;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return CertificatePage(
      title: strings.certificateChangedTitle,
      children: [
        CertificateWarning(
          strings.certificateChangedWarning(url.authority),
          danger: true,
        ),
        const SizedBox(height: 12),
        Text(strings.certificateChangedCauses),
        const SizedBox(height: 24),
        if (pinned case final pinned?) ...[
          Fingerprint(
            label: strings.certificateAcceptedFingerprint,
            sha256: pinned,
            copy: false,
          ),
          const SizedBox(height: 16),
        ],
        Fingerprint(
          label: strings.certificateNewFingerprint,
          sha256: certificate.sha256,
        ),
        const SizedBox(height: 8),
        Text(strings.certificateCompare),
        const SizedBox(height: 24),
        CertificateDetails(certificate),
        const SizedBox(height: 16),
        TrustDecision(
          statement: strings.certificateChangeChecked,
          accept: strings.certificateReplace,
          refuse: strings.certificateKeep,
          refusingIsPrimary: true,
          replacesPin: true,
          url: url,
          sha256: certificate.sha256,
        ),
      ],
    );
  }
}
