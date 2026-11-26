import 'package:core/core.dart';

import '../json_reading.dart';
import '../servarr_refs.dart';

/// A record of `GET queue`.
QueueItem queueItem(JsonObject record, ServarrRefs refs) {
  final status = switch (record['status']) {
    'delay' => QueueStatus.delayed,
    final word => QueueStatus.values.asNameMap()[word] ?? QueueStatus.unknown,
  };
  final severity = switch (record['trackedDownloadStatus']) {
    null => QueueSeverity.ok,
    final word =>
      QueueSeverity.values.asNameMap()[word] ?? QueueSeverity.unknown,
  };
  final size = optionalNumber(record, 'size') ?? 0;
  final sizeLeft = optionalNumber(record, 'sizeleft');
  return QueueItem(
    id: requireInt(record, 'id'),
    title: optionalString(record, 'title') ?? '',
    status: status,
    trackedState:
        TrackedState.values.asNameMap()[record['trackedDownloadState']] ??
        TrackedState.unknown,
    severity: severity,
    // Without what is left, nothing is known to have arrived.
    progress: QueueItem.progressFrom(size: size, sizeLeft: sizeLeft ?? size),
    sizeLeft: sizeLeft?.toInt() ?? 0,
    protocol:
        DownloadProtocol.values.asNameMap()[record['protocol']] ??
        DownloadProtocol.unknown,
    downloadId: optionalString(record, 'downloadId'),
    itemRef: refs.item,
    parent: refs.parent,
    eta: _timeSpan(optionalString(record, 'timeleft')),
    quality: _quality(record['quality']),
    downloadClient: optionalString(record, 'downloadClient'),
    messages: _messages(record),
    // As the services' web UI decides it.
    needsManualImport:
        status == QueueStatus.completed && severity == QueueSeverity.warning,
  );
}

/// `quality.quality` of a record.
Quality? _quality(Object? json) => switch (json) {
  {'quality': {'id': final int id, 'name': final String name}} => Quality(
    id: id,
    name: name,
  ),
  _ => null,
};

/// The error of the download client, then what each status message says: its
/// messages, or its title when it has none.
List<String> _messages(JsonObject record) {
  final messages = [?optionalString(record, 'errorMessage')];
  if (record['statusMessages'] case final List<Object?> entries) {
    for (final entry in entries.whereType<JsonObject>()) {
      final own = switch (entry['messages']) {
        final List<Object?> list => list.whereType<String>().toList(),
        _ => const <String>[],
      };
      if (own.isEmpty) {
        messages.addAll([?optionalString(entry, 'title')]);
      } else {
        messages.addAll(own);
      }
    }
  }
  return messages;
}

final _timeSpanPattern = RegExp(
  r'^(?:(\d{1,7})\.)?(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?$',
);

/// A .NET `TimeSpan`, `[d.]hh:mm:ss[.fffffff]`.
Duration? _timeSpan(String? text) {
  final match = text == null ? null : _timeSpanPattern.firstMatch(text);
  if (match == null) return null;
  int part(int group) => int.parse(match[group] ?? '0');
  return Duration(
    days: part(1),
    hours: part(2),
    minutes: part(3),
    seconds: part(4),
    // Ticks of 100 ns; a Duration holds microseconds.
    microseconds: int.parse((match[5] ?? '').padRight(7, '0')) ~/ 10,
  );
}
