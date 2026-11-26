/// Reading what the user types as a server's address.
library;

import 'package:core/core.dart';

/// Why a typed address cannot be used.
enum AddressProblem {
  /// Nothing was typed.
  missing,

  /// Not an http or https address of a host.
  invalid,

  /// A user name or password inside the address.
  userInfo,

  /// A `?` or `#` part.
  queryOrFragment,
}

final _whitespace = RegExp(r'\s');

// A scheme typed wrongly, such as `https:/host` or `http//host`.
final _brokenScheme = RegExp(r'^https?:?[/\\]', caseSensitive: false);

/// The address typed as [text], or why there is none.
///
/// Without a scheme, `http://` is put before it; the form shows the result.
/// Slashes at the end are dropped, and a sub-path is kept.
Result<Uri, AddressProblem> parseAddress(String text) {
  var value = text.trim();
  if (value.isEmpty) return const Err(AddressProblem.missing);
  if (value.contains(_whitespace)) return const Err(AddressProblem.invalid);
  if (!value.contains('://')) {
    // It would be read as a host named "http" or "https", reached over plain
    // http, and sent the key.
    if (value.startsWith(_brokenScheme)) {
      return const Err(AddressProblem.invalid);
    }
    value = 'http://$value';
  }
  final parsed = Uri.tryParse(value);
  if (parsed == null) return const Err(AddressProblem.invalid);
  if (parsed.userInfo.isNotEmpty) return const Err(AddressProblem.userInfo);
  if (parsed.hasQuery || parsed.hasFragment) {
    return const Err(AddressProblem.queryOrFragment);
  }
  final url = parsed.replace(
    path: parsed.path.replaceFirst(RegExp(r'/+$'), ''),
  );
  // A host that had to be escaped is a typing mistake.
  return isValidInstanceUrl(url) && !url.host.contains('%')
      ? Ok(url)
      : const Err(AddressProblem.invalid);
}
