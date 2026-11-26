import 'package:core/core.dart';

import '../json_reading.dart';

/// An entry of `GET health`.
HealthIssue healthIssue(JsonObject record) => HealthIssue(
  source: requireString(record, 'source'),
  level: HealthLevel.values.asNameMap()[record['type']] ?? HealthLevel.unknown,
  message: requireString(record, 'message'),
  helpUrl: switch (optionalString(record, 'wikiUrl')) {
    null || '' => null,
    final url => Uri.tryParse(url),
  },
);
