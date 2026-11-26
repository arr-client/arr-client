/// The part of the add and edit form about what the instance trusts.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import '../form_fields.dart';
import 'certificate_widgets.dart';

/// Shows the accepted certificate and the authority of the form, and offers to
/// import or remove them. An authority can be imported before any test.
class CertificateTrustSection extends StatelessWidget {
  const CertificateTrustSection({
    required this.pin,
    required this.customCa,
    required this.onImport,
    required this.onForgetPin,
    required this.onRemoveAuthority,
    super.key,
  });

  /// The accepted fingerprint for the address typed, if any.
  final String? pin;

  /// The authority, PEM.
  final String? customCa;

  final VoidCallback onImport;
  final VoidCallback onForgetPin;
  final VoidCallback onRemoveAuthority;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final authority = switch (customCa) {
      null => null,
      final pem => readCertificateAuthority(utf8.encode(pem)),
    };
    Widget button(IconData icon, String label, VoidCallback onPressed) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormHeading(strings.trustHeading),
        const SizedBox(height: 8),
        FormNote(strings.trustNote),
        if (pin case final pin?) ...[
          const SizedBox(height: 12),
          Fingerprint(
            label: strings.certificateAcceptedFingerprint,
            sha256: pin,
          ),
          button(
            Icons.remove_circle_outline,
            strings.trustForgetCertificate,
            onForgetPin,
          ),
        ],
        if (authority != null) ...[
          const SizedBox(height: 12),
          if (pin != null) ...[
            FormNote(strings.trustPinComesFirst),
            const SizedBox(height: 12),
          ],
          switch (authority) {
            Ok(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final certificate in value.certificates) ...[
                  CertificateDetails(certificate),
                  Fingerprint(
                    label: strings.trustAuthorityFingerprint,
                    sha256: certificate.sha256,
                  ),
                ],
              ],
            ),
            Err() => CertificateWarning(strings.trustAuthorityUnreadable),
          },
          button(
            Icons.remove_circle_outline,
            strings.trustRemoveAuthority,
            onRemoveAuthority,
          ),
        ],
        button(
          Icons.file_open_outlined,
          authority == null
              ? strings.trustImportAuthority
              : strings.trustReplaceAuthority,
          onImport,
        ),
      ],
    );
  }
}
