import 'package:core/core.dart';

import 'image_record.dart';
import 'json_fields.dart';

/// A record of `GET credit`.
Credit readCredit(JsonObject record) {
  final cast = record['type'] == 'cast';
  return Credit(
    person: requireText(record, 'personName'),
    // Radarr gives a cast member no job. The word is in the language of the
    // jobs it does give.
    role: cast
        ? 'Actor'
        : optionalText(record, 'job') ??
              optionalText(record, 'department') ??
              'Crew',
    character: cast ? optionalText(record, 'character') : null,
    image: readImages(record).firstOrNull,
  );
}
