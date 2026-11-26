/// What the add and edit form trusts, and what it has not yet let go of.
library;

import 'package:core/core.dart';

/// The accepted certificates and the authority of a form, by origin.
///
/// An accepted certificate that an authority is to replace is remembered until a
/// test has passed with that authority. Until then another certificate is still
/// a changed one, and saving keeps the accepted one unless the user says
/// otherwise: an authority that does not vouch for the server must not turn a
/// change into a first sight.
final class FormTrust {
  /// Starts from what [instance] has saved.
  FormTrust(Instance? instance) : customCa = instance?.customCa {
    if (instance case Instance(:final certPin?, :final url)) {
      _pins[url.origin] = certPin;
    }
  }

  /// The authority, PEM.
  String? customCa;

  /// The saved certificate stays while another address is tried.
  final _pins = <String, String>{};

  /// Those given up for an authority.
  final _replaced = <String, String>{};

  /// The authority a test passed with.
  final _proven = <String, String>{};

  /// The accepted certificate to connect to [url] with.
  String? pinFor(Uri url) => url.isScheme('https') ? _pins[url.origin] : null;

  /// The accepted certificate for [url]. Without an address, any there is.
  String? pinShown(Uri? url) =>
      url == null ? _pins.values.firstOrNull : _pins[url.origin];

  /// The certificate given up for [url] while no test has shown that the
  /// authority vouches for it.
  String? unprovenPin(Uri url) {
    if (!url.isScheme('https')) return null;
    final ca = customCa;
    if (ca != null && _proven[url.origin] == ca) return null;
    return _replaced[url.origin];
  }

  /// The user accepted [pin] for [url].
  void accept(Uri url, String pin) {
    _pins[url.origin] = pin;
    _replaced.remove(url.origin);
  }

  /// The user chose [pem], which takes the place of the certificate accepted
  /// for [url], or without an address of any.
  void useAuthority(Uri? url, String pem) {
    for (final origin in url == null ? [..._pins.keys] : [url.origin]) {
      if (_pins.remove(origin) case final pin?) _replaced[origin] = pin;
    }
    customCa = pem;
  }

  /// With no authority, nothing replaces the certificates given up for it.
  void removeAuthority() {
    customCa = null;
    for (final MapEntry(:key, :value) in _replaced.entries) {
      _pins.putIfAbsent(key, () => value);
    }
    _replaced.clear();
  }

  /// The user stops trusting the certificate accepted for [url], or without an
  /// address any.
  void forgetPin(Uri? url) {
    if (url == null) {
      _pins.clear();
      _replaced.clear();
    } else {
      _pins.remove(url.origin);
      _replaced.remove(url.origin);
    }
  }

  /// A test of [url] with [certPin] and [authority] passed.
  void testPassed(Uri url, {String? certPin, String? authority}) {
    if (url.isScheme('https') && certPin == null && authority != null) {
      _proven[url.origin] = authority;
    }
  }

  /// Whether the saved certificate of [instance] is no longer accepted.
  bool gaveUpSavedPin(Instance? instance) => switch (instance) {
    Instance(certPin: _?, :final url) => !_pins.containsKey(url.origin),
    _ => false,
  };
}
