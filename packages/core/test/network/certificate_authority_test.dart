/// Reading an imported certificate authority (T046, FR-005). The certificates
/// are described in certificates.dart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'certificates.dart';
import 'support.dart';

Result<CertificateAuthority, CertificateAuthorityProblem> _read(String text) =>
    readCertificateAuthority(utf8.encode(text));

CertificateAuthority _accepted(List<int> bytes) =>
    switch (readCertificateAuthority(bytes)) {
      Ok(:final value) => value,
      Err(:final error) => fail('Refused: $error'),
    };

List<int> _der(TestCertificate certificate) => base64.decode(
  certificate.pem.split('\n').where((line) => !line.startsWith('-')).join(),
);

void _refused(String text, CertificateAuthorityProblem problem) {
  expect(switch (_read(text)) {
    Ok() => null,
    Err(:final error) => error,
  }, problem);
}

/// An authority signed by another, which no file of certs/ is. Its keys and
/// its root's were thrown away.
const _intermediate = '''
-----BEGIN CERTIFICATE-----
MIIBijCCATCgAwIBAgIBBzAKBggqhkjOPQQDAjAfMR0wGwYDVQQDDBRhcnItY2xp
ZW50IHRlc3Qgcm9vdDAgFw0yNjExMjYxNzI5MjZaGA8yMTI2MTEwMjE3MjkyNlow
JzElMCMGA1UEAwwcYXJyLWNsaWVudCB0ZXN0IGludGVybWVkaWF0ZTBZMBMGByqG
SM49AgEGCCqGSM49AwEHA0IABPwi0zDx5YEwar7elFPToQRdT2+8h2MnO+syn1AX
kXQGsMvzzGilB4EyguCkVEIOhpg3wTBubPGbmhsVJh6hA3mjUzBRMA8GA1UdEwEB
/wQFMAMBAf8wHQYDVR0OBBYEFKGNdvzi1jMcB/d+d/XLTjPiKfK/MB8GA1UdIwQY
MBaAFHpBVeVUeamCaDrw9E8U9iTsh8aYMAoGCCqGSM49BAMCA0gAMEUCIQCb/wSB
2OnqEJBDV1Izdvu35s72H985UIc7YfYt/PvIKAIgGyhFuuzRchTw9wvJPg3golGL
JYIG/jI0Dxn951WiNE4=
-----END CERTIFICATE-----
''';

void main() {
  test('says whose the certificate is, how long and its fingerprint', () {
    final authority = _accepted(utf8.encode(TestCertificate.ca.pem));

    final certificate = authority.certificates.single;
    expect(certificate.sha256, TestCertificate.ca.sha256);
    expect(certificate.subject, contains('CN=arr-client test CA'));
    expect(certificate.issuer, certificate.subject);
    expect(certificate.notBefore, DateTime.utc(2025));
    expect(certificate.notAfter, DateTime.utc(2125));
  });

  // What a server presents is described by dart:io: both must agree.
  test('describes a certificate as a connection does', () async {
    final server = await TlsServer.start(
      TestCertificate.selfSigned.serverContext(),
    );
    final client = clientFor(settingsFor(server.url()));
    final seen = expectFailure<CertificateUntrusted>(await client.send(get()))
        .certificate;

    final read = _accepted(utf8.encode(TestCertificate.selfSigned.pem))
        .certificates
        .single;

    expect(read.sha256, seen.sha256);
    expect(read.subject, seen.subject);
    expect(read.issuer, seen.issuer);
    expect(read.notBefore!.isAtSameMomentAs(seen.notBefore!), isTrue);
    expect(read.notAfter!.isAtSameMomentAs(seen.notAfter!), isTrue);
  });

  test('takes the DER form and stores PEM', () {
    final authority = _accepted(_der(TestCertificate.ca));

    expect(authority.certificates.single.sha256, TestCertificate.ca.sha256);
    expect(authority.pem, startsWith('-----BEGIN CERTIFICATE-----\n'));
  });

  test('takes a bundle, once each, and keeps only the certificates', () {
    final authority = _accepted(
      utf8.encode(
        'Home authority\n${TestCertificate.ca.pem}\n'
        'Old one\n${TestCertificate.otherCa.pem}${TestCertificate.ca.pem}',
      ),
    );

    expect(
      [for (final certificate in authority.certificates) certificate.sha256],
      [TestCertificate.ca.sha256, TestCertificate.otherCa.sha256],
    );
    expect(authority.pem, isNot(contains('authority')));
    expect('BEGIN'.allMatches(authority.pem), hasLength(2));
  });

  // A paste into a one-line field loses the line breaks.
  test('takes PEM whose line breaks became spaces', () {
    final text = TestCertificate.ca.pem.replaceAll('\n', ' ');

    expect(
      _accepted(utf8.encode(text)).certificates.single.sha256,
      TestCertificate.ca.sha256,
    );
  });

  test('what it stores is trusted for connecting', () async {
    final server = await TlsServer.start(TestCertificate.leaf.serverContext());
    final authority = _accepted(_der(TestCertificate.ca));
    final client = clientFor(
      settingsFor(server.url(), customCa: authority.pem),
    );

    expectOk(await client.send(get()));
  });

  test('refuses a certificate that another signed for a server', () {
    final leaf = TestCertificate.leaf;

    _refused(leaf.pem, CertificateAuthorityProblem.notAnAuthority);
    // As in a server's full chain.
    _refused(
      '${leaf.pem}${TestCertificate.ca.pem}',
      CertificateAuthorityProblem.notAnAuthority,
    );
    expect(switch (readCertificateAuthority(_der(leaf))) {
      Ok() => null,
      Err(:final error) => error,
    }, CertificateAuthorityProblem.notAnAuthority);
  });

  test('takes an authority that another signed', () {
    final certificate = _accepted(utf8.encode(_intermediate)).certificates;

    expect(certificate.single.subject, contains('test intermediate'));
    expect(certificate.single.issuer, contains('test root'));
  });

  // Trusting one lets exactly its server in, by name and dates.
  test('takes a self-signed certificate', () {
    final certificate = TestCertificate.selfSigned;

    final authority = _accepted(utf8.encode(certificate.pem));

    expect(authority.certificates.single.sha256, certificate.sha256);
  });

  test('refuses a private key, also beside a certificate', () {
    final key = File('test/network/certs/leaf.key').readAsStringSync();

    _refused(key, CertificateAuthorityProblem.privateKey);
    _refused(
      '${TestCertificate.ca.pem}$key',
      CertificateAuthorityProblem.privateKey,
    );
  });

  test('refuses what is not a certificate', () {
    final pem = TestCertificate.ca.pem;
    for (final text in [
      '',
      'not a certificate',
      '0 not DER either',
      '-----BEGIN CERTIFICATE-----\nMIIB',
      '-----BEGIN CERTIFICATE-----\nbm9uc2Vuc2U=\n-----END CERTIFICATE-----',
      // A whole one does not excuse a damaged one.
      '$pem-----BEGIN CERTIFICATE-----\nMIIB',
      '$pem${pem.replaceFirst('MII', '???')}',
    ]) {
      _refused(text, CertificateAuthorityProblem.notACertificate);
    }
    final der = _der(TestCertificate.ca);
    for (final length in [1, 2, 40, der.length - 1]) {
      expect(
        readCertificateAuthority(der.sublist(0, length)),
        isA<Err<CertificateAuthority, CertificateAuthorityProblem>>(),
      );
    }
  });

  test('refuses more than can be saved', () {
    _refused('a' * (256 * 1024 + 1), CertificateAuthorityProblem.tooLarge);
  });
}
