/// The records of manual import: what the server says of a file, what can be
/// chosen for it and what is sent back.
library;

import 'package:core/core.dart';

import '../json_reading.dart';
import '../records/quality_record.dart';
import 'servarr_import_mapping.dart';

/// A record of `GET manualimport`.
ManualImportCandidate importCandidate(
  JsonObject record,
  ServarrImportMapping mapping,
) {
  final match = mapping.match(record);
  return ManualImportCandidate(
    path: requireString(record, 'path'),
    size: optionalNumber(record, 'size')?.toInt() ?? 0,
    downloadId: optionalString(record, 'downloadId'),
    matchedRef: match.item,
    episodeIds: match.episodeIds,
    quality: recordQuality(record['quality']),
    languages: _languages(record['languages']),
    rejections: _rejections(record['rejections']),
    rawJson: record,
  );
}

/// [sent] as [record], of the answer to `POST manualimport`, now has it.
///
/// The answer has no size and no folder name, so those stay.
ManualImportCandidate reprocessedCandidate(
  ManualImportCandidate sent,
  JsonObject record,
  ServarrImportMapping mapping,
) {
  final match = mapping.match(record);
  return ManualImportCandidate(
    path: sent.path,
    size: sent.size,
    downloadId: sent.downloadId,
    selected: sent.selected,
    matchedRef: match.item,
    episodeIds: match.episodeIds,
    quality: recordQuality(record['quality']),
    languages: _languages(record['languages']),
    rejections: _rejections(record['rejections']),
    rawJson: {...sent.rawJson, ...record},
  );
}

/// A record of `GET qualitydefinition`.
Quality definedQuality(JsonObject record) =>
    recordQuality(record) ??
    (throw const FormatException('A quality is missing'));

/// A record of `GET language`.
Language readLanguage(JsonObject record) =>
    Language(id: requireInt(record, 'id'), name: requireString(record, 'name'));

/// What both `POST manualimport` and the import command say of [candidate]:
/// its corrections, and of the server's record only what the import needs.
JsonObject importEntry(
  ManualImportCandidate candidate,
  ServarrImportMapping mapping,
) {
  final raw = candidate.rawJson;
  return {
    'path': candidate.path,
    'downloadId': ?candidate.downloadId,
    'quality': ?_sentQuality(candidate),
    'languages': [
      for (final language in candidate.languages)
        {'id': language.id, 'name': language.name},
    ],
    for (final field in const ['releaseGroup', 'indexerFlags', 'releaseType'])
      if (raw.containsKey(field)) field: raw[field],
    ...mapping.ids(candidate),
  };
}

/// The record's quality as it is, unless the user chose another; that one has
/// the record's revision.
Object? _sentQuality(ManualImportCandidate candidate) {
  final recorded = candidate.rawJson['quality'];
  final chosen = candidate.quality;
  if (chosen == null || chosen.id == recordQuality(recorded)?.id) {
    return recorded;
  }
  return {
    'quality': {'id': chosen.id, 'name': chosen.name},
    if (recorded case {'revision': final Object revision}) 'revision': revision,
  };
}

List<Language> _languages(Object? json) => [
  if (json is List<Object?>)
    for (final entry in json)
      if (entry case {'id': final int id, 'name': final String name})
        Language(id: id, name: name),
];

List<String> _rejections(Object? json) => [
  if (json is List<Object?>)
    for (final entry in json)
      if (entry case {'reason': final String reason}) reason,
];
