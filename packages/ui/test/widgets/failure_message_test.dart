import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'app.dart';

void main() {
  testWidgets('every failure has its own message', (tester) async {
    await tester.pumpWidget(testApp(const SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    const certificate = CertificateInfo(sha256: '00');
    const failures = <ServiceFailure>[
      Unreachable(),
      DnsFailure(),
      CertificateUntrusted(certificate),
      CertificateChanged(certificate),
      AuthFailed(),
      Forbidden(),
      WrongService(),
      ProxyInterception(),
      Redirected(),
      HostRejected(),
      UnsupportedVersion(),
      WritesRefused(),
      PermissionDenied(),
      NotFound(),
      Conflict(),
      Validation([]),
      ServerError(),
      MalformedResponse(),
      OutcomeUnknown(),
    ];

    final messages = {
      for (final failure in failures) failureMessage(context, failure),
    };

    expect(messages, hasLength(failures.length));
  });

  testWidgets('includes what the server or module said', (tester) async {
    await tester.pumpWidget(testApp(const SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    String message(ServiceFailure failure) => failureMessage(context, failure);

    expect(
      message(AuthFailed(hint: (_) => 'The address may be banned.')),
      endsWith('\nThe address may be banned.'),
    );
    expect(
      message(const Redirected(host: 'login.example.test')),
      contains('login.example.test'),
    );
    expect(message(const UnsupportedVersion(version: '3.2')), contains('3.2'));
    expect(
      message(const Validation(['Path is taken', 'Tag is unknown'])),
      endsWith(':\nPath is taken\nTag is unknown'),
    );
    expect(message(const ServerError(statusCode: 503)), contains('error 503.'));
  });
}
