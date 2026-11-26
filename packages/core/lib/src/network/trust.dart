/// Which certificates an instance accepts (research R4).
///
/// An https connection is opened here and handed to [HttpClient] only once its
/// certificate has been accepted, so that no byte of a request, and with it no
/// credential, reaches a server before that.
///
/// `badCertificateCallback` of [HttpClient] would not do: it is not called for a
/// chain the system trusts, which a pin may still have to refuse, and it may be
/// given an issuer instead of the leaf.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../module/service_failure.dart';
import 'certificate_info.dart';

/// A server's certificate was not accepted. Nothing was written to the
/// connection, which is closed.
final class CertificateRefusal implements Exception {
  /// Creates a [CertificateRefusal].
  const CertificateRefusal(this.failure);

  /// A [CertificateUntrusted] or [CertificateChanged] of the leaf certificate.
  final ServiceFailure failure;
}

/// A client whose https connections are all checked: against [certPin] alone if
/// there is one, and else against the system's roots and [customCa].
///
/// Its connections are pooled, so it must not be used for settings with another
/// pin or authority. It uses no proxy.
///
/// Throws a [TlsException] if the authority is needed and cannot be read.
HttpClient newHttpClient({String? certPin, String? customCa}) {
  // Null is the default context, with the system's roots.
  final context = certPin == null && customCa != null
      ? (SecurityContext(withTrustedRoots: true)
          ..setTrustedCertificatesBytes(utf8.encode(customCa)))
      : null;
  return HttpClient()
    ..idleTimeout = const Duration(seconds: 3)
    // The default takes a proxy from the environment.
    ..findProxy = ((_) => 'DIRECT')
    ..connectionFactory = (url, proxyHost, proxyPort) {
      // The line above rules this out. Through a tunnel, TLS would start only
      // after this function, unchecked.
      if (proxyHost != null) {
        throw const SocketException('Proxies are not supported');
      }
      return url.isScheme('https')
          ? _connectSecurely(url, context, certPin)
          : Socket.startConnect(url.host, url.port);
    };
}

Future<ConnectionTask<Socket>> _connectSecurely(
  Uri url,
  SecurityContext? context,
  String? certPin,
) async {
  var chainFailed = false;
  final task = await SecureSocket.startConnect(
    url.host,
    url.port,
    context: context,
    // The handshake is let through so that the leaf can be read, as this is
    // given whichever certificate of the chain failed. The socket is destroyed
    // below unless the certificate is accepted, before anything is written.
    onBadCertificate: (_) {
      chainFailed = true;
      return true;
    },
  );
  var cancelled = false;
  final checked = task.socket.then<Socket>((socket) {
    final leaf = socket.peerCertificate;
    final info = leaf == null ? null : _describe(leaf);
    final accepted =
        info != null &&
        (certPin == null ? !chainFailed : info.sha256 == certPin);
    if (accepted && !cancelled) return socket;

    socket.destroy();
    if (cancelled) throw const SocketException('Connection cancelled');
    if (info == null) throw const HandshakeException('No certificate');
    throw CertificateRefusal(
      certPin == null ? CertificateUntrusted(info) : CertificateChanged(info),
    );
  });
  return ConnectionTask.fromSocket(checked, () {
    // The task cannot stop a handshake under way: its socket is dropped above.
    cancelled = true;
    task.cancel();
  });
}

CertificateInfo _describe(X509Certificate certificate) => CertificateInfo(
  sha256: sha256.convert(certificate.der).toString(),
  subject: certificate.subject,
  issuer: certificate.issuer,
  notBefore: certificate.startValidity,
  notAfter: certificate.endValidity,
);
