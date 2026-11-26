import 'package:core/core.dart';

import '../json_reading.dart';
import '../servarr_refs.dart';

/// A record of `GET history`.
HistoryEvent historyEvent(JsonObject record, ServarrRefs refs) => HistoryEvent(
  id: requireInt(record, 'id'),
  eventType: _eventType(record['eventType']),
  date: DateTime.parse(requireString(record, 'date')).toUtc(),
  itemRef: refs.item,
  downloadId: optionalString(record, 'downloadId'),
  sourceTitle: optionalString(record, 'sourceTitle') ?? '',
  details: _details(record['data']),
);

HistoryEventType _eventType(Object? word) => switch (word) {
  'grabbed' => HistoryEventType.grabbed,
  'downloadFolderImported' ||
  'movieFolderImported' ||
  'seriesFolderImported' => HistoryEventType.imported,
  'downloadFailed' => HistoryEventType.failed,
  'movieFileRenamed' || 'episodeFileRenamed' => HistoryEventType.renamed,
  'movieFileDeleted' || 'episodeFileDeleted' => HistoryEventType.deleted,
  _ => HistoryEventType.other,
};

/// The text values of `data`, without any that may hold a secret.
///
/// A grab records the indexer's download address, which carries the user's key
/// for that indexer in its query or its path. So every value with an address in
/// it is left out, as is every value under a name for an address or a secret,
/// and whatever [SecretRedactor] would remove.
Map<String, String> _details(Object? data) => {
  if (data is JsonObject)
    for (final MapEntry(:key, :value) in data.entries)
      if (value is String && !_isSecretName(key) && !_holdsSecret(value))
        key: value,
};

// A release's guid is usually its address at the indexer.
final _secretName = RegExp(
  'url|guid|magnet|key|token|passw|passphrase|secret|cookie|credential|'
  'authorization|session|headers|torrentpass|'
  r'^(auth|pass|pwd|sid|sig|signature)$',
);

bool _isSecretName(String name) =>
    _secretName.hasMatch(name.toLowerCase().replaceAll(RegExp('[-_]'), ''));

// Also percent-encoded, as inside another address.
final _address = RegExp('://|%3a%2f%2f|magnet:', caseSensitive: false);

final _redactor = SecretRedactor();

bool _holdsSecret(String value) =>
    _address.hasMatch(value) || _redactor.redact(value) != value;
