/// Tolerant reading of the fields of a record. What a record cannot do without
/// throws [FormatException]; anything else of the wrong type counts as left out.
library;

import 'package:core/core.dart';

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

/// The objects listed in [field].
Iterable<JsonObject> objectsIn(JsonObject record, String field) =>
    switch (record[field]) {
      final List<Object?> list => list.whereType<JsonObject>(),
      _ => const [],
    };
