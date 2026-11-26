/// The certificates in `certs/`, recreated by `certs/generate.sh`.
///
/// `leaf*` are signed by [TestCertificate.ca]; `selfSigned*` sign themselves.
library;

import 'dart:convert';
import 'dart:io';

/// One certificate file and the SHA-256 of its DER form.
enum TestCertificate {
  ca('ca', '16e5dc835a6431a2a38a8a20086a12a4141fd52ada0abc0a9be0ee1c94e9add9'),
  otherCa(
    'other_ca',
    'ab62cd6c91692d53d88b68f1c8734d7969da48a38123bf7544a3a75ff7a79275',
  ),
  leaf(
    'leaf',
    '7086886a12668c89658a9423a57e475a8250f30128d02b215ed2652c5385ed75',
  ),
  leafRenewed(
    'leaf_renewed',
    'd8148b81806c41598c9674bdcc395dc7f5c6c969436566c7e73c1e03441c88ce',
  ),
  leafWrongHost(
    'leaf_wrong_host',
    '24d748f5484daf55d06516422314daaa2131ada1b87404b927201460af999036',
  ),
  leafExpired(
    'leaf_expired',
    '828b016f2f315759574c864e26196ba1be7dec89ca0cc32189decca23848f009',
  ),
  selfSigned(
    'self_signed',
    'bfdcef9e5018ee2c03c2ee622ed9deea2e37e5a058ea2d17360842fcd7ab61e7',
  ),
  selfSignedOther(
    'self_signed_other',
    '7818468aa9633e86d39a16622cf821fcaf2778814bcddd005a9caede48097ea5',
  ),

  /// Expired, and for another host.
  selfSignedStale(
    'self_signed_stale',
    '8f60b00af7dd38ed7e2e9b23a7c586453777013e4f17c5f1b516272aa114fade',
  );

  const TestCertificate(this.file, this.sha256);

  final String file;
  final String sha256;

  // Tests run in the package's directory.
  static const _directory = 'test/network/certs';

  String get pem => File('$_directory/$file.pem').readAsStringSync();

  /// What a server presenting this certificate needs. With [withCa], it also
  /// sends the issuing authority.
  SecurityContext serverContext({bool withCa = false}) => SecurityContext()
    ..useCertificateChainBytes(utf8.encode('$pem${withCa ? ca.pem : ''}'))
    ..usePrivateKey('$_directory/$file.key');
}
