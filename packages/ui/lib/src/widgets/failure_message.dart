import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import '../l10n/generated/ui_localizations.dart';

/// What happened and what to do next, in the viewer's language.
///
/// [context] must be below the app's localizations.
String failureMessage(BuildContext context, ServiceFailure failure) {
  final l10n = UiLocalizations.of(context);
  return switch (failure) {
    Unreachable() => l10n.failureUnreachable,
    DnsFailure() => l10n.failureDns,
    CertificateUntrusted() => l10n.failureCertificateUntrusted,
    CertificateChanged() => l10n.failureCertificateChanged,
    AuthFailed(:final hint) => [
      l10n.failureAuth,
      if (hint != null) hint(context),
    ].join('\n'),
    Forbidden() => l10n.failureForbidden,
    WrongService() => l10n.failureWrongService,
    ProxyInterception() => l10n.failureProxy,
    Redirected(:final host?) => l10n.failureRedirectedTo(host),
    Redirected() => l10n.failureRedirected,
    HostRejected() => l10n.failureHostRejected,
    UnsupportedVersion(:final version?) => l10n.failureUnsupportedVersionNumber(
      version,
    ),
    UnsupportedVersion() => l10n.failureUnsupportedVersion,
    WritesRefused() => l10n.failureWritesRefused,
    PermissionDenied() => l10n.failureLocalNetworkPermission,
    NotFound() => l10n.failureNotFound,
    Conflict() => l10n.failureConflict,
    Validation(messages: []) => l10n.failureValidation,
    Validation(:final messages) => l10n.failureValidationMessages(
      messages.join('\n'),
    ),
    ServerError(:final statusCode?) => l10n.failureServerStatus('$statusCode'),
    ServerError() => l10n.failureServer,
    MalformedResponse() => l10n.failureMalformed,
    OutcomeUnknown() => l10n.failureOutcomeUnknown,
  };
}
