/// How the columns of data-model.md EventMarker are written.
library;

import 'dart:convert';

import '../models/availability.dart';
import '../models/history_event.dart';
import '../models/media_request.dart';
import '../models/request_status.dart';

/// EventMarker.lastSeenCursor: how far the history has been read. The id tells
/// what is new; the date, which is the server's, is what to ask since. Null
/// while the history has had nothing.
typedef HistoryCursor = ({int id, DateTime date});

/// The [cursor] moved past [events].
HistoryCursor? advanceCursor(
  HistoryCursor? cursor,
  Iterable<HistoryEvent> events,
) {
  var moved = cursor;
  for (final HistoryEvent(:id, :date) in events) {
    moved = moved == null
        ? (id: id, date: date)
        : (
            id: id > moved.id ? id : moved.id,
            date: date.isAfter(moved.date) ? date : moved.date,
          );
  }
  return moved;
}

/// [cursor] as stored.
String? encodeCursor(HistoryCursor? cursor) => cursor == null
    ? null
    : jsonEncode({
        'id': cursor.id,
        'date': cursor.date.toUtc().toIso8601String(),
      });

/// The cursor stored as [text].
HistoryCursor? decodeCursor(String? text) {
  if (text == null) return null;
  final json = jsonDecode(text) as Map<String, Object?>;
  return (
    id: json['id']! as int,
    date: DateTime.parse(json['date']! as String),
  );
}

/// The severity of an open condition, least first. Names are persisted.
enum ConditionSeverity {
  /// Needs attention.
  warning,

  /// Failed.
  error;

  /// Whether a condition last seen as [before], or not at all, is to be
  /// notified.
  bool risesFrom(ConditionSeverity? before) =>
      before == null || index > before.index;
}

/// EventMarker.openKeys as stored.
String encodeOpenKeys(Map<String, ConditionSeverity> keys) => jsonEncode({
  for (final MapEntry(:key, :value) in keys.entries) key: value.name,
});

/// The open conditions stored as [text].
Map<String, ConditionSeverity> decodeOpenKeys(String text) => {
  for (final MapEntry(:key, :value)
      in (jsonDecode(text) as Map<String, Object?>).entries)
    key: ConditionSeverity.values.byName(value! as String),
};

/// What EventMarker.requestSnapshot holds of one request.
typedef RequestState = ({RequestStatus status, Availability availability});

/// The state of [request].
RequestState requestState(MediaRequest request) =>
    (status: request.status, availability: request.availability);

/// EventMarker.requestSnapshot as stored.
String encodeSnapshot(Map<int, RequestState> snapshot) => jsonEncode({
  for (final MapEntry(:key, :value) in snapshot.entries)
    '$key': {
      'status': value.status.name,
      'availability': value.availability.name,
    },
});

/// The requests stored as [text].
Map<int, RequestState> decodeSnapshot(String text) => {
  for (final MapEntry(:key, :value)
      in (jsonDecode(text) as Map<String, Object?>).entries)
    int.parse(key): _state(value! as Map<String, Object?>),
};

RequestState _state(Map<String, Object?> json) => (
  status: RequestStatus.values.byName(json['status']! as String),
  availability: Availability.values.byName(json['availability']! as String),
);
