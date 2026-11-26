/// Certificate trust (T024: research R4, FR-005, constitution III). All of it
/// is reached through [InstanceHttpClient]; the tests need nothing else of
/// trust.dart. The API is described in client_test.dart.
///
/// - Without `certPin` and `customCa`, the system's roots decide.
/// - `customCa` (PEM) is trusted in addition, for that client only, with the
///   usual checks of chain, host name and dates.
/// - `certPin` is the SHA-256 of the DER form of the leaf certificate, 64
///   lower-case hex digits. When set it alone decides, whatever the chain, host
///   name, dates and `customCa` say.
/// - A refused certificate gets no application byte: [CertificateChanged] when
///   a pin is set, else [CertificateUntrusted], each describing the leaf. This
///   holds for writes too, which are then not [OutcomeUnknown].
/// - [CertificateInfo.subject] and `issuer` contain the common names, in any
///   format.
///
/// The servers record what they decrypt, so "nothing was sent" is observed at
/// the socket. The certificates are described in certificates.dart.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'certificates.dart';
import 'support.dart';

/// Sends and expects the certificate to be refused with nothing sent.
Future<F> _refused<F extends ServiceFailure>(
  TlsServer server, {
  String? certPin,
  String? customCa,
  HttpMethod method = HttpMethod.get,
}) async {
  final client = clientFor(
    settingsFor(server.url(), certPin: certPin, customCa: customCa),
  );
  final result = await client.send(request(method));

  await server.closedByClient();
  expect(server.connections, greaterThan(0));
  expect(server.bytes, isEmpty);
  expect(expectError(result).response, isNull);
  return expectFailure<F>(result);
}

/// Sends and expects the request, with its credential, to arrive.
Future<void> _accepted(
  TlsServer server, {
  String? certPin,
  String? customCa,
}) async {
  final client = clientFor(
    settingsFor(server.url(), certPin: certPin, customCa: customCa),
  );

  expect(expectOk(await client.send(get())).text, '{}');

  expect(server.received, startsWith('GET /api '));
  expect(server.received.toLowerCase(), contains('x-api-key: $apiKey'));
}

Future<TlsServer> _serving(
  TestCertificate certificate, {
  bool withCa = false,
}) => TlsServer.start(certificate.serverContext(withCa: withCa));

void main() {
  test('an unknown self-signed certificate is shown, not used', () async {
    final server = await _serving(TestCertificate.selfSigned);

    final failure = await _refused<CertificateUntrusted>(server);

    final certificate = failure.certificate;
    expect(certificate.sha256, TestCertificate.selfSigned.sha256);
    expect(certificate.subject, contains('self_signed'));
    expect(certificate.issuer, contains('self_signed'));
    expect(certificate.notBefore?.isAtSameMomentAs(DateTime.utc(2025)), isTrue);
    expect(certificate.notAfter?.isAtSameMomentAs(DateTime.utc(2125)), isTrue);
  });

  test('the certificate shown is the leaf, not its issuer', () async {
    final server = await _serving(TestCertificate.leaf, withCa: true);

    final failure = await _refused<CertificateUntrusted>(server);

    expect(failure.certificate.sha256, TestCertificate.leaf.sha256);
    expect(failure.certificate.issuer, contains('arr-client test CA'));
  });

  group('pinning', () {
    for (final certificate in [
      TestCertificate.selfSigned,
      TestCertificate.selfSignedStale,
    ]) {
      test('accepts the pinned ${certificate.file}', () async {
        final server = await _serving(certificate);

        await _accepted(server, certPin: certificate.sha256);
      });
    }

    for (final method in HttpMethod.values) {
      test('sends no byte of a ${method.name} before a match', () async {
        final server = await _serving(TestCertificate.selfSignedOther);

        final failure = await _refused<CertificateChanged>(
          server,
          certPin: TestCertificate.selfSigned.sha256,
          method: method,
        );

        expect(
          failure.certificate.sha256,
          TestCertificate.selfSignedOther.sha256,
        );
      });
    }

    test('is of the leaf: the issuer does not match', () async {
      final server = await _serving(TestCertificate.leaf, withCa: true);

      await _refused<CertificateChanged>(
        server,
        certPin: TestCertificate.ca.sha256,
      );
    });

    test('refuses what the authority would accept', () async {
      final server = await _serving(TestCertificate.leaf);

      await _refused<CertificateChanged>(
        server,
        certPin: TestCertificate.selfSigned.sha256,
        customCa: TestCertificate.ca.pem,
      );
    });

    test('accepts what the authority would refuse', () async {
      final server = await _serving(TestCertificate.selfSigned);

      await _accepted(
        server,
        certPin: TestCertificate.selfSigned.sha256,
        customCa: TestCertificate.otherCa.pem,
      );
    });

    // A resumed TLS session would not be checked again.
    test('refuses again on the next send', () async {
      final server = await _serving(TestCertificate.selfSigned);
      for (final certPin in [TestCertificate.selfSignedOther.sha256, null]) {
        final client = clientFor(settingsFor(server.url(), certPin: certPin));

        expectError(await client.send(get()));
        expectError(await client.send(get()));
      }

      await server.closedByClient();
      expect(server.connections, 4);
      expect(server.bytes, isEmpty);
    });

    test('applies to its own instance only', () async {
      final server = await _serving(TestCertificate.selfSigned);
      final pinned = clientFor(
        settingsFor(server.url(), certPin: TestCertificate.selfSigned.sha256),
      );
      final other = clientFor(settingsFor(server.url()));
      expectOk(await pinned.send(get()));
      final sent = server.bytes.length;

      expectFailure<CertificateUntrusted>(await other.send(get()));

      await pause();
      expect(server.bytes, hasLength(sent));
    });

    test('is checked again when the settings change', () async {
      final server = await _serving(TestCertificate.selfSigned);
      var settings = settingsFor(
        server.url(),
        certPin: TestCertificate.selfSigned.sha256,
      );
      final client = loadingClient(() async => settings);
      expectOk(await client.send(get()));
      final sent = server.bytes.length;

      // The server keeps the first connection open.
      settings = settingsFor(
        server.url(),
        certPin: TestCertificate.selfSignedOther.sha256,
      );
      expectFailure<CertificateChanged>(await client.send(get()));
      await pause();
      expect(server.bytes, hasLength(sent));

      settings = settingsFor(server.url());
      expectFailure<CertificateUntrusted>(await client.send(get()));
      await pause();
      expect(server.bytes, hasLength(sent));
    });

    test('does not carry a redirect to another origin', () async {
      final target = await _serving(TestCertificate.selfSigned);
      final server = await TlsServer.start(
        TestCertificate.selfSigned.serverContext(),
        response:
            'HTTP/1.1 302 Found\r\n'
            'location: ${target.url('/steal')}\r\n'
            'content-length: 0\r\n'
            '\r\n',
      );
      final client = clientFor(
        settingsFor(server.url(), certPin: TestCertificate.selfSigned.sha256),
      );

      expectFailure<Redirected>(await client.send(get()));

      await pause();
      expect(target.connections, 0);
    });
  });

  group('a custom authority', () {
    for (final certificate in [
      TestCertificate.leaf,
      TestCertificate.leafRenewed,
    ]) {
      test('accepts ${certificate.file}, which it signed', () async {
        final server = await _serving(certificate);

        await _accepted(server, customCa: TestCertificate.ca.pem);
      });
    }

    for (final (name, certificate, authority) in [
      ('of another authority', TestCertificate.leaf, TestCertificate.otherCa),
      ('signed by itself', TestCertificate.selfSigned, TestCertificate.ca),
      ('for another host', TestCertificate.leafWrongHost, TestCertificate.ca),
      ('that has expired', TestCertificate.leafExpired, TestCertificate.ca),
    ]) {
      test('does not accept a certificate $name', () async {
        final server = await _serving(certificate);

        final failure = await _refused<CertificateUntrusted>(
          server,
          customCa: authority.pem,
          method: HttpMethod.post,
        );

        expect(failure.certificate.sha256, certificate.sha256);
      });
    }

    test('applies to its own instance only', () async {
      final server = await _serving(TestCertificate.leaf);
      await _accepted(server, customCa: TestCertificate.ca.pem);
      final sent = server.bytes.length;
      final other = clientFor(settingsFor(server.url()));

      expectFailure<CertificateUntrusted>(await other.send(get()));

      await pause();
      expect(server.bytes, hasLength(sent));
    });

    // Not even to a server that the system's roots might accept.
    for (final (name, authority) in [
      ('empty', ''),
      ('not a certificate', 'not a certificate'),
      ('cut off', '-----BEGIN CERTIFICATE-----\nMIIB'),
    ]) {
      test('that is $name opens no connection', () async {
        final server = await _serving(TestCertificate.leaf);
        final client = clientFor(
          settingsFor(server.url(), customCa: authority),
        );

        expectError(await client.send(get()));

        await pause();
        expect(server.connections, 0);
      });
    }

    test('that is not a certificate sends nothing', () async {
      final server = await _serving(TestCertificate.leaf);
      final client = clientFor(
        settingsFor(server.url(), customCa: 'not a certificate'),
      );

      expectError(await client.send(get()));

      await pause();
      expect(server.bytes, isEmpty);
    });
  });

  test('a proxy of the environment gets nothing over https', () async {
    final proxy = await RawServer.start();
    final server = await _serving(TestCertificate.selfSigned);

    await HttpOverrides.runZoned(
      () => _accepted(server, certPin: TestCertificate.selfSigned.sha256),
      findProxyFromEnvironment: (_, _) => 'PROXY 127.0.0.1:${proxy.port}',
    );

    expect(proxy.connections, 0);
  });
}
