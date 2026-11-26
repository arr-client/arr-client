/// What the form says about a failed test: which of the failures happened and
/// what to do next (spec story 1, FR-007).
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// A short name of the failure and the advice that goes with it.
typedef FailureText = ({String title, String message});

/// [service] is the name of the service that was expected, [authKind] what was
/// tested with.
FailureText testFailureText(
  BuildContext context,
  ServiceFailure failure, {
  required String service,
  required AuthKind authKind,
}) {
  final strings = AppLocalizations.of(context);
  // What the shared widgets say already fits where this does not override it.
  String shared() => failureMessage(context, failure);
  FailureText text(String title, [String? message]) =>
      (title: title, message: message ?? shared());
  return switch (failure) {
    Unreachable() => text(
      strings.testUnreachableTitle,
      strings.testUnreachable,
    ),
    DnsFailure() => text(strings.testDnsTitle),
    CertificateUntrusted() => text(
      strings.testCertificateUntrustedTitle,
      strings.testCertificateUntrusted,
    ),
    CertificateChanged() => text(
      strings.testCertificateChangedTitle,
      strings.testCertificateChanged,
    ),
    AuthFailed(:final hint) => (
      title: authKind == AuthKind.apiKey
          ? strings.testApiKeyRejectedTitle
          : strings.testSignInRejectedTitle,
      message: [
        authKind == AuthKind.apiKey
            ? strings.testApiKeyRejected
            : strings.testSignInRejected,
        if (hint != null) hint(context),
      ].join('\n'),
    ),
    Forbidden() => text(strings.testForbiddenTitle),
    WrongService() => text(
      strings.testWrongServiceTitle(service),
      strings.testWrongService(service),
    ),
    ProxyInterception() => text(strings.testProxyTitle),
    Redirected() => text(strings.testRedirectedTitle),
    HostRejected() => text(strings.testHostRejectedTitle),
    UnsupportedVersion() => text(strings.testVersionTitle),
    PermissionDenied() => text(strings.testPermissionTitle),
    ServerError() => text(strings.testServerErrorTitle),
    MalformedResponse() => text(strings.testMalformedTitle),
    Validation() => text(strings.testValidationTitle),
    // Not what a test gets; named all the same.
    NotFound() ||
    Conflict() ||
    WritesRefused() ||
    OutcomeUnknown() => text(strings.testFailedTitle),
  };
}
