/// Puts the answers of several services into one list.
///
/// Dates are converted to the device's time zone before anything is grouped by
/// day: some are instants in UTC, others already local midnight. The order
/// depends only on the dates, the order of the instances and each server's own
/// order, never on which service answered first.
library;

import 'package:core/core.dart';

import 'service_answer.dart';
import 'today.dart';

/// A release and the name of the service that has it.
typedef DatedRelease = ({CalendarEvent event, String service});

/// An import and the name of the service that made it.
typedef DatedImport = ({ImportedItem item, String service});

/// The releases of each local day that has any, earliest day first.
Map<DateTime, List<DatedRelease>> releasesByDay(
  ServiceAnswers<CalendarEvent> answers,
) {
  final releases = _ordered<CalendarEvent, DatedRelease>(
    answers,
    (event, service) => (event: event, service: service),
    (a, b) => a.event.date.compareTo(b.event.date),
  );
  final days = <DateTime, List<DatedRelease>>{};
  for (final release in releases) {
    (days[dayOf(release.event.date)] ??= []).add(release);
  }
  return days;
}

/// The imports of all services, newest first.
List<DatedImport> importsNewestFirst(ServiceAnswers<ImportedItem> answers) =>
    _ordered<ImportedItem, DatedImport>(
      answers,
      (item, service) => (item: item, service: service),
      (a, b) => b.item.importedAt.compareTo(a.item.importedAt),
    );

List<R> _ordered<T, R>(
  ServiceAnswers<T> answers,
  R Function(T value, String service) pair,
  int Function(R a, R b) compare,
) {
  final all = [
    for (final answer in answers)
      for (final value in answer.value ?? <T>[]) pair(value, answer.name),
  ];
  // `List.sort` is not stable, so the position breaks ties.
  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final order = compare(a.$2, b.$2);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
  return [for (final (_, value) in indexed) value];
}
