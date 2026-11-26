import 'history_event_type.dart';
import 'item_ref.dart';

/// An entry of the history.
final class HistoryEvent {
  /// Creates a [HistoryEvent].
  const HistoryEvent({
    required this.id,
    required this.eventType,
    required this.date,
    required this.sourceTitle,
    this.itemRef,
    this.downloadId,
    this.details = const {},
  });

  /// The server's id of the event.
  final int id;

  /// What happened.
  final HistoryEventType eventType;

  /// When, from the server.
  final DateTime date;

  /// The item concerned.
  final ItemRef? itemRef;

  /// The download concerned.
  final String? downloadId;

  /// The release's title.
  final String sourceTitle;

  /// Further values the server gives.
  final Map<String, String> details;
}
