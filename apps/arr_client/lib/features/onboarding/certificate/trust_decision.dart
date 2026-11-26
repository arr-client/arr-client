/// The part of a review in which a certificate is accepted.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import '../certificate_review.dart';
import 'authority_import_screen.dart';

/// Accepting takes two deliberate steps: the user states [statement], then the
/// button is enabled. The way back that trusts nothing is always open, and is
/// the primary button if [refusingIsPrimary].
class TrustDecision extends StatefulWidget {
  const TrustDecision({
    required this.statement,
    required this.accept,
    required this.refuse,
    required this.url,
    required this.sha256,
    this.refusingIsPrimary = false,
    this.replacesPin = false,
    super.key,
  });

  /// What the user states to have done.
  final String statement;

  /// The label of the button that accepts.
  final String accept;

  /// The label of the button that trusts nothing.
  final String refuse;

  final Uri url;

  /// The fingerprint that is accepted.
  final String sha256;

  final bool refusingIsPrimary;

  /// A certificate is accepted already, which an authority would replace.
  final bool replacesPin;

  @override
  State<TrustDecision> createState() => _TrustDecisionState();
}

class _TrustDecisionState extends State<TrustDecision> {
  var _stated = false;

  Future<void> _useAuthority() async {
    final pem = await importAuthority(
      context,
      url: widget.url,
      replacesPin: widget.replacesPin,
    );
    if (pem == null || !mounted) return;
    Navigator.pop(context, CertificateTrust.authority(pem));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final accept = _stated
        ? () => Navigator.pop(
            context,
            CertificateTrust.certificate(widget.sha256),
          )
        : null;
    void refuse() => Navigator.pop(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _stated,
          onChanged: (value) => setState(() => _stated = value ?? false),
          title: Text(widget.statement),
        ),
        const SizedBox(height: 12),
        if (widget.refusingIsPrimary) ...[
          FilledButton(onPressed: refuse, child: Text(widget.refuse)),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: accept,
            child: Text(widget.accept),
          ),
        ] else ...[
          FilledButton(onPressed: accept, child: Text(widget.accept)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: refuse, child: Text(widget.refuse)),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => unawaited(_useAuthority()),
          child: Text(strings.certificateUseAuthority),
        ),
      ],
    );
  }
}
