import 'package:core/core.dart';

import 'image_record.dart';
import 'json_fields.dart';

/// A record of `GET credit`.
Credit readCredit(JsonObject record) {
  final type =
      CreditType.values.asNameMap()[record['type']] ?? CreditType.unknown;
  return Credit(
    person: requireText(record, 'personName'),
    type: type,
    // Radarr gives a cast member neither.
    role: optionalText(record, 'job') ?? optionalText(record, 'department'),
    character: type == CreditType.cast
        ? optionalText(record, 'character')
        : null,
    image: readImages(record).firstOrNull,
  );
}
