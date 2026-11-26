/// What the calendar reads from the active profile's services. Home can read
/// the same providers.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'service_answer.dart';
import 'service_read_notifier.dart';
import 'today.dart';

/// The releases dated from `from` up to, but not including, `to`.
typedef DateRange = ({DateTime from, DateTime to});

/// The releases of every service with a calendar; null while switching profile.
final calendarEventsProvider = NotifierProvider.autoDispose
    .family<
      CalendarReadNotifier<CalendarEvent>,
      ServiceAnswers<CalendarEvent>?,
      DateRange
    >(_EventsNotifier.new);

/// How many days, the first included, the agenda lists.
final agendaDaysProvider = NotifierProvider.autoDispose<AgendaDays, int>(
  AgendaDays.new,
);

/// The releases of the agenda's days from the given one on. Asking for more
/// days reads again with what is on screen kept.
final agendaEventsProvider = NotifierProvider.autoDispose
    .family<
      CalendarReadNotifier<CalendarEvent>,
      ServiceAnswers<CalendarEvent>?,
      DateTime
    >(_AgendaNotifier.new);

/// What every service with a calendar imported on one local day, given as its
/// local midnight; null while switching profile.
final importedOnProvider = NotifierProvider.autoDispose
    .family<
      CalendarReadNotifier<ImportedItem>,
      ServiceAnswers<ImportedItem>?,
      DateTime
    >(_ImportsNotifier.new);

/// Counts the refreshes the user has asked for.
final calendarRefreshProvider = NotifierProvider<CalendarRefresh, int>(
  CalendarRefresh.new,
);

class CalendarRefresh extends Notifier<int> {
  @override
  int build() => 0;

  /// Has everything on screen read again.
  void request() => state++;
}

class AgendaDays extends Notifier<int> {
  static const _step = 30;

  @override
  int build() => _step;

  /// Lists later days too.
  void extend() => state += _step;
}

class _AgendaNotifier extends CalendarReadNotifier<CalendarEvent> {
  _AgendaNotifier(this.from);

  final DateTime from;

  @override
  ServiceAnswers<CalendarEvent>? build() {
    ref.listen(agendaDaysProvider, (_, _) => unawaited(reload()));
    return super.build();
  }

  @override
  ServiceResult<List<CalendarEvent>> read(CalendarProvider provider) =>
      provider.events(from, addDays(from, ref.read(agendaDaysProvider)));
}

class _EventsNotifier extends CalendarReadNotifier<CalendarEvent> {
  _EventsNotifier(this.range);

  final DateRange range;

  @override
  ServiceResult<List<CalendarEvent>> read(CalendarProvider provider) =>
      provider.events(range.from, range.to);
}

class _ImportsNotifier extends CalendarReadNotifier<ImportedItem> {
  _ImportsNotifier(this.day);

  final DateTime day;

  @override
  ServiceResult<List<ImportedItem>> read(CalendarProvider provider) =>
      provider.importedOn(day);
}

/// One read from every service with a calendar (see [ServiceReadNotifier]).
abstract class CalendarReadNotifier<T>
    extends ServiceReadNotifier<CalendarProvider, T> {
  @override
  CapabilityKind<CalendarProvider> get kind => CapabilityKind.calendar;
}
