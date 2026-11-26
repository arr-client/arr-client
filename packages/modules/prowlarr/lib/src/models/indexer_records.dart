/// Reading the records only Prowlarr has. What a record cannot do without
/// throws [FormatException]; anything else of the wrong type counts as left
/// out.
///
/// An indexer's record also holds its settings, credentials included. Nothing
/// of them is read or kept.
library;

import 'package:core/core.dart';

/// [json] as a list of objects.
List<JsonObject> objects(Object? json) => json is List<Object?>
    ? [for (final entry in json) _object(entry)]
    : throw const FormatException('Not a list');

JsonObject _object(Object? json) =>
    json is JsonObject ? json : throw const FormatException('Not an object');

int _requireInt(JsonObject record, String field) => switch (record[field]) {
  final int value => value,
  _ => throw const FormatException('A number is missing'),
};

String _requireString(JsonObject record, String field) =>
    switch (record[field]) {
      final String value => value,
      _ => throw const FormatException('A text is missing'),
    };

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// When an indexer last failed, and until when the server avoids it.
typedef IndexerFailure = ({DateTime? until, DateTime? last});

/// The entries of `GET indexerstatus`, by indexer. The server has one only for
/// an indexer that failed.
Map<int, IndexerFailure> indexerFailures(Object? json) => {
  for (final record in objects(json))
    _requireInt(record, 'indexerId'): (
      until: _time(record['disabledTill']),
      last: _time(record['mostRecentFailure']),
    ),
};

/// The records of `GET indexer`, in the server's order, each with its failure
/// out of [failures].
List<Indexer> indexerRecords(Object? json, Map<int, IndexerFailure> failures) =>
    [
      for (final record in objects(json))
        _indexer(record, failures[_requireInt(record, 'id')]),
    ];

Indexer _indexer(JsonObject record, IndexerFailure? failure) => Indexer(
  id: _requireInt(record, 'id'),
  name: _requireString(record, 'name'),
  protocol:
      DownloadProtocol.values.asNameMap()[record['protocol']] ??
      DownloadProtocol.unknown,
  enabled: record['enable'] == true,
  failureUntil: failure?.until,
  lastFailure: failure?.last,
);

/// `GET indexer/categories`, each category followed by its subcategories.
List<IndexerCategory> categoryRecords(Object? json) => [
  for (final record in objects(json)) ...[
    _category(record),
    if (record['subCategories'] case final List<Object?> subcategories)
      for (final subcategory in objects(subcategories)) _category(subcategory),
  ],
];

IndexerCategory _category(JsonObject record) => IndexerCategory(
  id: _requireInt(record, 'id'),
  name: _requireString(record, 'name'),
);
