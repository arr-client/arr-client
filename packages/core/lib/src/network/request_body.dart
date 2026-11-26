/// What a request sends.
sealed class RequestBody {
  const RequestBody();
}

/// Sent as `application/json`.
final class JsonBody extends RequestBody {
  /// Creates a [JsonBody].
  const JsonBody(this.value);

  /// Anything `jsonEncode` accepts.
  final Object? value;
}

/// Sent as `application/x-www-form-urlencoded`.
final class FormBody extends RequestBody {
  /// Creates a [FormBody].
  const FormBody(this.fields);

  /// Names and values of the form.
  final Map<String, String> fields;
}
