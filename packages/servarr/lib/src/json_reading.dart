/// Tolerant reading of decoded JSON. What a record cannot do without throws
/// [FormatException]; anything else of the wrong type counts as left out.
library;

import 'package:core/core.dart';

/// [json] as an object.
JsonObject asObject(Object? json) =>
    json is JsonObject ? json : throw const FormatException('Not an object');

/// [json] as a list of objects.
List<JsonObject> asObjects(Object? json) => json is List<Object?>
    ? [for (final entry in json) asObject(entry)]
    : throw const FormatException('Not a list');

/// The whole number in [field].
int requireInt(JsonObject object, String field) => switch (object[field]) {
  final int value => value,
  _ => throw const FormatException('A number is missing'),
};

/// The text in [field].
String requireString(JsonObject object, String field) =>
    optionalString(object, field) ??
    (throw const FormatException('A text is missing'));

/// The text in [field], if there is one.
String? optionalString(JsonObject object, String field) =>
    switch (object[field]) {
      final String value => value,
      _ => null,
    };

/// The finite number in [field], if there is one.
num? optionalNumber(JsonObject object, String field) => switch (object[field]) {
  final num value when value.isFinite => value,
  _ => null,
};

/// A page of a paged list, each record read by [read].
({List<T> records, int pageSize, int totalRecords}) readPage<T>(
  Object? json,
  T Function(JsonObject record) read,
) {
  final page = asObject(json);
  final pageSize = requireInt(page, 'pageSize');
  if (pageSize <= 0) throw const FormatException('Not a page size');
  return (
    records: asObjects(page['records']).map(read).toList(),
    pageSize: pageSize,
    totalRecords: requireInt(page, 'totalRecords'),
  );
}
