/// What a request sends.
sealed class RequestBody {
  const RequestBody();
}

/// Sent as `application/json`.
final class JsonBody extends RequestBody {
  const JsonBody(this.value);

  /// Anything `jsonEncode` accepts.
  final Object? value;
}

/// Sent as `application/x-www-form-urlencoded`.
final class FormBody extends RequestBody {
  const FormBody(this.fields);

  final Map<String, String> fields;
}
