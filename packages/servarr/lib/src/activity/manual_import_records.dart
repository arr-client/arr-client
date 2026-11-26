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

/// A record of `GET qualitydefinition` as the id of its quality and the whole
/// `quality` object, which a write has to send.
MapEntry<int, JsonObject> qualityById(JsonObject record) =>
    MapEntry(definedQuality(record).id, asObject(record['quality']));

/// The id of the quality chosen for [candidate], if it is not the record's.
int? correctedQualityId(ManualImportCandidate candidate) {
  final chosen = candidate.quality?.id;
  return chosen == recordQuality(candidate.rawJson['quality'])?.id
      ? null
      : chosen;
}

/// What both `POST manualimport` and the import command say of [candidate]:
/// its corrections, and of the server's record only what the import needs.
///
/// [qualities] must have the [correctedQualityId] of the candidate.
JsonObject importEntry(
  ManualImportCandidate candidate,
  ServarrImportMapping mapping,
  Map<int, JsonObject> qualities,
) {
  final raw = candidate.rawJson;
  return {
    'path': candidate.path,
    'downloadId': ?candidate.downloadId,
    'quality': ?_sentQuality(candidate, qualities),
    'languages': [
      for (final language in candidate.languages)
        {'id': language.id, 'name': language.name},
    ],
    for (final field in const ['releaseGroup', 'indexerFlags', 'releaseType'])
      if (raw.containsKey(field)) field: raw[field],
    ...mapping.ids(candidate),
  };
}

/// The record's quality as it is, unless the user chose another: then that one
/// as the server defines it, with the record's revision. The server takes the
/// source and resolution from what is sent, not from the id.
Object? _sentQuality(
  ManualImportCandidate candidate,
  Map<int, JsonObject> qualities,
) {
  final recorded = candidate.rawJson['quality'];
  final corrected = correctedQualityId(candidate);
  if (corrected == null) return recorded;
  return {
    'quality': qualities[corrected],
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
