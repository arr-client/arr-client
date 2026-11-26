import 'package:core/core.dart';

import '../json_reading.dart';
import '../records/quality_record.dart';

/// A record of `GET release`, found by searching for [target]. Without its guid
/// and indexer it cannot be grabbed, so it is not understood.
Release releaseRecord(JsonObject record, Map<String, int> target) => Release(
  guid: requireString(record, 'guid'),
  indexerId: requireInt(record, 'indexerId'),
  indexer: optionalString(record, 'indexer') ?? '',
  title: optionalString(record, 'title') ?? '',
  protocol:
      DownloadProtocol.values.asNameMap()[record['protocol']] ??
      DownloadProtocol.unknown,
  size: optionalNumber(record, 'size')?.toInt() ?? 0,
  ageHours: optionalNumber(record, 'ageHours')?.toDouble() ?? 0,
  quality: recordQuality(record['quality']),
  languages: [
    if (record['languages'] case final List<Object?> languages)
      for (final language in languages)
        if (language case {'id': final int id, 'name': final String name})
          Language(id: id, name: name),
  ],
  score: optionalNumber(record, 'customFormatScore')?.toInt() ?? 0,
  seeders: optionalNumber(record, 'seeders')?.toInt(),
  leechers: optionalNumber(record, 'leechers')?.toInt(),
  rejections: [
    if (record['rejections'] case final List<Object?> rejections)
      ...rejections.whereType<String>(),
  ],
  rawJson: record,
  searchTarget: target,
  downloadAllowed: record['downloadAllowed'] != false,
);
