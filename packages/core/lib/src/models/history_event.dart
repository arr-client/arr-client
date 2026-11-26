import 'history_event_type.dart';
import 'item_ref.dart';

/// An entry of the history.
final class HistoryEvent {
  const HistoryEvent({
    required this.id,
    required this.eventType,
    required this.date,
    required this.sourceTitle,
    this.itemRef,
    this.downloadId,
    this.details = const {},
  });

  final int id;

  final HistoryEventType eventType;

  final DateTime date;

  final ItemRef? itemRef;

  final String? downloadId;

  final String sourceTitle;

  final Map<String, String> details;
}
