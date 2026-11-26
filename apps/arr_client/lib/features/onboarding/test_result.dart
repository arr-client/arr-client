/// How the test went, above the buttons of the form.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'failure_text.dart';
import 'instance_form_controller.dart';

class TestResult extends StatelessWidget {
  const TestResult({
    required this.status,
    required this.service,
    this.onReviewCertificate,
    super.key,
  });

  final TestStatus status;

  /// The name of the service that was expected.
  final String service;

  /// Shows the certificate of a failed test.
  final VoidCallback? onReviewCertificate;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    switch (status) {
      case NotTested():
        return const SizedBox.shrink();
      case Testing():
        return Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.testRunning),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ),
        );
      case TestPassed(:final probe):
        return _Panel(
          icon: Icons.check_circle_outline,
          color: theme.colorScheme.primary,
          title: strings.testPassed(probe.product, probe.version),
          message: probe.newerThanTested ? strings.testNewerVersion : null,
        );
      case TestFailed(:final failure, :final input):
        final text = testFailureText(
          context,
          failure,
          service: service,
          authKind: input.authKind,
        );
        final isCertificate =
            failure is CertificateUntrusted || failure is CertificateChanged;
        return _Panel(
          icon: Icons.error_outline,
          color: theme.colorScheme.error,
          title: text.title,
          message: text.message,
          action: isCertificate && onReviewCertificate != null
              ? OutlinedButton(
                  onPressed: onReviewCertificate,
                  child: Text(strings.testReviewCertificate),
                )
              : null,
        );
    }
  }
}

/// An icon, so that the outcome does not rest on colour, and text.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.color,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Icon(icon, color: color)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        if (message case final message?) ...[
                          const SizedBox(height: 4),
                          Text(message),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (action case final action?) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
