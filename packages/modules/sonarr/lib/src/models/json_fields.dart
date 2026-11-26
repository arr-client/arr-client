/// Tolerant reading of the fields of a record. What a record cannot do without
/// throws [FormatException]; anything else of the wrong type counts as left out.
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
int requireInt(JsonObject record, String field) => switch (record[field]) {
  final int value => value,
  _ => throw const FormatException('A number is missing'),
};

/// The text in [field], which may not be empty.
String requireText(JsonObject record, String field) =>
    optionalText(record, field) ??
    (throw const FormatException('A text is missing'));

/// The text in [field]; null if there is none or it is empty.
String? optionalText(JsonObject record, String field) =>
    switch (record[field]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };

/// The finite number in [field], if there is one.
num? optionalNumber(JsonObject record, String field) => switch (record[field]) {
  final num value when value.isFinite => value,
  _ => null,
};

/// The number in [field] if it is a positive whole one. Sonarr writes zero for
/// a number it does not know.
int? optionalPositive(JsonObject record, String field) =>
    switch (record[field]) {
      final int value when value > 0 => value,
      _ => null,
    };
