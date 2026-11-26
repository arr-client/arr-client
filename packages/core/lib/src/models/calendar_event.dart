import 'calendar_date_kind.dart';
import 'item_ref.dart';
import 'item_state.dart';

/// A dated release.
final class CalendarEvent {
  const CalendarEvent({
    required this.itemRef,
    required this.title,
    required this.date,
    required this.dateKind,
    required this.state,
  });

  final ItemRef itemRef;

  final String title;

  final DateTime date;

  final CalendarDateKind dateKind;

  final ItemState state;
}
