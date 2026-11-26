/// The rules of data-model.md for one value at a time. Rules that compare with
/// other records are in the repository.
library;

import 'dart:convert';

import '../module/module_category.dart';
import '../module/module_descriptor.dart';
import 'auth_kind.dart';
import 'credential.dart';

/// The largest custom certificate authority, in bytes of UTF-8.
const maximumCustomCaBytes = 64 * 1024;

// An HTTP token, RFC 9110.
final _token = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

/// Whether a profile or instance name has 1 to 40 characters.
bool hasValidNameLength(String name) =>
    name.isNotEmpty && name.runes.length <= 40;

/// Whether two names are the same, ignoring case.
bool isSameName(String a, String b) => a.toLowerCase() == b.toLowerCase();

/// Whether [url] can be an instance's address.
bool isValidInstanceUrl(Uri url) =>
    (url.isScheme('http') || url.isScheme('https')) &&
    url.host.isNotEmpty &&
    url.userInfo.isEmpty &&
    !url.hasQuery &&
    !url.hasFragment &&
    url.port > 0 &&
    url.port <= 65535;

/// Whether the scheme, host or port differs.
bool isOtherOrigin(Uri a, Uri b) =>
    a.scheme != b.scheme || a.host != b.host || a.port != b.port;

/// Whether [customCa] is small enough to store.
bool fitsCustomCa(String customCa) =>
    utf8.encode(customCa).length <= maximumCustomCaBytes;

/// Whether a custom header may be called [name].
bool isValidHeaderName(String name) =>
    _token.hasMatch(name) &&
    !const {'host', 'content-length'}.contains(name.toLowerCase());

/// Whether an instance of a service may not use basic authentication, as its
/// API key goes in the same header, `Authorization`.
bool excludesBasicAuth(ModuleDescriptor module, AuthKind authKind) =>
    authKind == AuthKind.apiKey &&
    module.apiKeyHeader?.name.toLowerCase() == 'authorization';

/// Whether [credential] has basic authentication.
bool hasBasicAuth(Credential credential) =>
    credential.basicUser != null || credential.basicPassword != null;

/// Whether a subtitle instance may link to a module of [category].
bool isSubtitleTarget(ModuleCategory category) =>
    category == ModuleCategory.movies || category == ModuleCategory.series;
