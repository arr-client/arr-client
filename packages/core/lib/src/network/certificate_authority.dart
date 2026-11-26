/// Reading a file or pasted text as a private certificate authority, and
/// describing what is in it, so that the user sees what they are about to
/// trust.
///
/// `dart:io` can load a certificate as trusted but says nothing about it, so
/// the few fields to show are read from the DER form here. Nothing here decides
/// what is trusted: that is TLS's, in `trust.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../instances/instance_rules.dart';
import '../module/result.dart';
import 'certificate_info.dart';

/// The certificates of an authority, and the text to store as
/// `Instance.customCa`.
final class CertificateAuthority {
  const CertificateAuthority._(this.pem, this.certificates);

  /// The certificates alone, as PEM: nothing else of the input is kept.
  final String pem;

  /// What each certificate says, in the order given. Never empty.
  final List<CertificateInfo> certificates;
}

/// Why an input cannot be an authority.
enum CertificateAuthorityProblem {
  /// No certificate, or one that cannot be read.
  notACertificate,

  /// It holds a private key, which must not be stored or exported.
  privateKey,

  /// More than can be saved with an instance.
  tooLarge,
}

// A bundle may carry a text description beside each certificate.
const _maximumInputBytes = 4 * maximumCustomCaBytes;

const _begin = '-----BEGIN CERTIFICATE-----';

final _block = RegExp('$_begin([A-Za-z0-9+/=\\s]*)-----END CERTIFICATE-----');

/// Reads [bytes] as one or more PEM certificates, or as one in DER form.
Result<CertificateAuthority, CertificateAuthorityProblem>
readCertificateAuthority(List<int> bytes) {
  if (bytes.length > _maximumInputBytes) {
    return const Err(CertificateAuthorityProblem.tooLarge);
  }
  const refused = Err<CertificateAuthority, CertificateAuthorityProblem>(
    CertificateAuthorityProblem.notACertificate,
  );
  // Byte for character: PEM is ASCII, and the rest is not looked at.
  final text = latin1.decode(bytes, allowInvalid: true);
  if (text.contains('PRIVATE KEY-----')) {
    return const Err(CertificateAuthorityProblem.privateKey);
  }

  final List<List<int>> found;
  try {
    final blocks = _block.allMatches(text).toList();
    // One that is cut off or damaged must not be left out unnoticed.
    if (blocks.length != _begin.allMatches(text).length) return refused;
    found = [
      for (final block in blocks)
        base64.decode(block.group(1)!.replaceAll(RegExp(r'\s'), '')),
      // A DER certificate begins with a sequence.
      if (blocks.isEmpty && bytes.isNotEmpty && bytes.first == 0x30) bytes,
    ];
  } on FormatException {
    return refused;
  }
  if (found.isEmpty) return refused;

  final certificates = <String, CertificateInfo>{};
  final pem = StringBuffer();
  for (final der in found) {
    final CertificateInfo info;
    try {
      info = _describe(der);
    } on FormatException {
      return refused;
    }
    if (certificates.containsKey(info.sha256)) continue;
    certificates[info.sha256] = info;
    pem.writeln(_begin);
    final encoded = base64.encode(der);
    for (var start = 0; start < encoded.length; start += 64) {
      final end = start + 64;
      pem.writeln(
        encoded.substring(start, end < encoded.length ? end : encoded.length),
      );
    }
    pem.writeln('-----END CERTIFICATE-----');
  }

  final result = pem.toString();
  if (!fitsCustomCa(result)) {
    return const Err(CertificateAuthorityProblem.tooLarge);
  }
  try {
    // What connecting will do with it.
    SecurityContext().setTrustedCertificatesBytes(utf8.encode(result));
  } on TlsException {
    return refused;
  }
  return Ok(
    CertificateAuthority._(result, List.unmodifiable(certificates.values)),
  );
}

/// One DER element: its tag and contents.
typedef _Element = ({int tag, List<int> body});

/// The elements that follow each other in [bytes].
List<_Element> _elements(List<int> bytes) {
  final elements = <_Element>[];
  var at = 0;
  int next() {
    if (at >= bytes.length) throw const FormatException('Cut off');
    return bytes[at++];
  }

  while (at < bytes.length) {
    final tag = next();
    var length = next();
    if (length >= 0x80) {
      final count = length & 0x7f;
      if (count == 0 || count > 3) throw const FormatException('Length');
      length = 0;
      for (var index = 0; index < count; index++) {
        length = (length << 8) | next();
      }
    }
    if (at + length > bytes.length) throw const FormatException('Cut off');
    elements.add((tag: tag, body: bytes.sublist(at, at + length)));
    at += length;
  }
  return elements;
}

const _sequence = 0x30;

List<_Element> _inside(_Element element, [int tag = _sequence]) {
  if (element.tag != tag) throw const FormatException('Unexpected element');
  return _elements(element.body);
}

/// The fields of the certificate [der] (RFC 5280, section 4.1).
CertificateInfo _describe(List<int> der) {
  final outer = _elements(der);
  if (outer.length != 1) throw const FormatException('Not one certificate');
  final certificate = _inside(outer.single);
  if (certificate.length != 3) throw const FormatException('Not a certificate');
  final signed = _inside(certificate.first);
  // The version, tagged [0], is left out by version 1 certificates.
  final first = signed.isNotEmpty && signed.first.tag == 0xa0 ? 1 : 0;
  if (signed.length < first + 6) {
    throw const FormatException('Not a certificate');
  }
  // Serial number, signature algorithm, issuer, validity, subject, key.
  final validity = _inside(signed[first + 3]);
  if (validity.length != 2) throw const FormatException('Validity');
  return CertificateInfo(
    sha256: sha256.convert(der).toString(),
    issuer: _name(signed[first + 2]),
    notBefore: _time(validity[0]),
    notAfter: _time(validity[1]),
    subject: _name(signed[first + 4]),
  );
}

const _attributes = {
  '85.4.3': 'CN',
  '85.4.6': 'C',
  '85.4.7': 'L',
  '85.4.8': 'ST',
  '85.4.10': 'O',
  '85.4.11': 'OU',
};

/// A name as `/O=Home/CN=nas`, the form `X509Certificate` gives for a server's
/// certificate. Attributes other than the common ones are left out.
String _name(_Element name) {
  final text = StringBuffer();
  for (final set in _inside(name)) {
    for (final pair in _inside(set, 0x31)) {
      final parts = _inside(pair);
      if (parts.length != 2) throw const FormatException('Name');
      final label = _attributes[parts[0].body.join('.')];
      if (label != null) text.write('/$label=${_string(parts[1])}');
    }
  }
  return text.toString();
}

String _string(_Element element) => switch (element.tag) {
  // UTF8String
  0x0c => utf8.decode(element.body, allowMalformed: true),
  // BMPString
  0x1e => String.fromCharCodes([
    for (var at = 0; at + 1 < element.body.length; at += 2)
      (element.body[at] << 8) | element.body[at + 1],
  ]),
  _ => latin1.decode(element.body),
};

final _utcTime = RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$');
final _generalizedTime = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$',
);

DateTime _time(_Element element) {
  final pattern = switch (element.tag) {
    0x17 => _utcTime,
    0x18 => _generalizedTime,
    _ => throw const FormatException('Time'),
  };
  final match = pattern.firstMatch(latin1.decode(element.body));
  if (match == null) throw const FormatException('Time');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  var year = parts[0];
  // Two digits mean 1950 to 2049.
  if (element.tag == 0x17) year += year < 50 ? 2000 : 1900;
  return DateTime.utc(year, parts[1], parts[2], parts[3], parts[4], parts[5]);
}
