import 'package:core/core.dart';

import '../json_reading.dart';
import '../records/quality_record.dart';
import '../servarr_refs.dart';

/// A record of `GET blocklist`.
BlocklistEntry blocklistEntry(JsonObject record, ServarrRefs refs) =>
    BlocklistEntry(
      id: requireInt(record, 'id'),
      sourceTitle: optionalString(record, 'sourceTitle') ?? '',
      date: DateTime.parse(requireString(record, 'date')).toUtc(),
      // A Sonarr entry names its series but no one episode.
      itemRef: refs.item ?? refs.parent,
      quality: recordQuality(record['quality']),
      reason: optionalString(record, 'message'),
    );
