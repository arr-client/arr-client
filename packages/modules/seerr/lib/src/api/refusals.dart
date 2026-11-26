/// Telling apart the refusals of Seerr, Overseerr and Jellyseerr
/// (contracts/upstream-apis.md). Bodies are read and never logged: some hold
/// password hashes.
library;

import 'dart:convert';

import 'package:core/core.dart';

/// The body of [response] if it is a JSON object, else null.
Map<String, Object?>? jsonObjectOf(ServiceResponse response) {
  try {
    final value = jsonDecode(response.text);
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}

/// What a missing session or permission and a wrong API key all get. Other 403s,
/// such as a used up quota, say why in `message`.
bool isNoPermission(ServiceResponse response) =>
    response.statusCode == 403 &&
    jsonObjectOf(response)?['error'] ==
        'You do not have permission to access this endpoint';

/// A write without a CSRF token the server accepts (research R18). It says
/// nothing about the credential.
bool isCsrfRefusal(ServiceResponse response) =>
    response.statusCode == 403 &&
    jsonObjectOf(response)?['message'] == 'invalid csrf token';
