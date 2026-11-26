import 'dart:convert';

import '../src/network/request_body.dart';
import 'param_rule.dart';

/// What the body of a permitted request may be.
sealed class BodyRule {
  const BodyRule();

  /// No body.
  const factory BodyRule.none() = _NoBody;

  /// Any JSON.
  const factory BodyRule.json() = _AnyJson;

  /// A JSON object whose fields named in [fields] satisfy their rules. Other
  /// fields are free, since an edit sends back the whole resource, but none may
  /// differ from a named one only in case: servers may ignore case.
  const factory BodyRule.jsonObject(Map<String, ParamRule> fields) =
      _JsonObject;

  /// A form with no field outside [fields].
  const factory BodyRule.form(Map<String, ParamRule> fields) = _Form;

  /// Whether [body] is permitted.
  bool permits(RequestBody? body);
}

final class _NoBody extends BodyRule {
  const _NoBody();

  @override
  bool permits(RequestBody? body) => body == null;
}

final class _AnyJson extends BodyRule {
  const _AnyJson();

  @override
  bool permits(RequestBody? body) => body is JsonBody;
}

final class _JsonObject extends BodyRule {
  const _JsonObject(this.fields);

  final Map<String, ParamRule> fields;

  @override
  bool permits(RequestBody? body) {
    if (body is! JsonBody) return false;
    final sent = _asSent(body.value);
    if (sent is! Map<String, Object?>) return false;

    final lowerCased = {for (final name in fields.keys) name.toLowerCase()};
    final disguised = sent.keys.any(
      (name) =>
          !fields.containsKey(name) && lowerCased.contains(name.toLowerCase()),
    );
    return !disguised &&
        fields.entries.every((field) {
          if (!sent.containsKey(field.key)) return !field.value.required;
          return switch (sent[field.key]) {
            final String value => field.value.permits([value]),
            final num value => field.value.permits(['$value']),
            final bool value => field.value.permits(['$value']),
            // Null, a list or an object is not one of a set of values.
            final other =>
              field.value.values == null &&
                  (!field.value.nonEmpty || _holdsSomething(other)),
          };
        });
  }

  static bool _holdsSomething(Object? value) => switch (value) {
    final List<Object?> list =>
      list.isNotEmpty &&
          list.every(
            (item) => item != null && !(item is String && item.trim().isEmpty),
          ),
    final Map<Object?, Object?> map => map.isNotEmpty,
    _ => false,
  };

  // What would be sent, which a `toJson` method decides. Null if it cannot be,
  // so that the request is refused and reported like any other.
  static Object? _asSent(Object? value) {
    try {
      return jsonDecode(jsonEncode(value));
    } on JsonUnsupportedObjectError {
      return null;
    }
  }
}

final class _Form extends BodyRule {
  const _Form(this.fields);

  final Map<String, ParamRule> fields;

  @override
  bool permits(RequestBody? body) =>
      body is FormBody &&
      ParamRule.permitsAll(fields, {
        for (final field in body.fields.entries) field.key: [field.value],
      });
}
