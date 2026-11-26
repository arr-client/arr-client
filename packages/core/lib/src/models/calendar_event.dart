import 'calendar_date_kind.dart';
import 'item_ref.dart';
import 'item_state.dart';

/// A dated release.
final class CalendarEvent {
  /// Creates a [CalendarEvent].
  const CalendarEvent({
    required this.itemRef,
    required this.title,
    required this.date,
    required this.dateKind,
    required this.state,
  });

  /// The item released.
  final ItemRef itemRef;

  /// Title to show.
  final String title;

  /// When.
  final DateTime date;

  /// What the date marks.
  final CalendarDateKind dateKind;

  /// The item's state.
  final ItemState state;
}
