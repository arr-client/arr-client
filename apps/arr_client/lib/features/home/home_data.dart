/// What Home reads beyond what the calendar and the queue already do.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../calendar/calendar_data.dart';
import '../calendar/service_answer.dart';
import '../calendar/service_read_notifier.dart';
import '../calendar/today.dart';

/// How many days, today included, Home looks ahead for releases.
const upcomingDays = 30;

/// The releases Home lists as coming up, from [today] on.
DateRange upcomingRange(DateTime today) =>
    (from: today, to: addDays(today, upcomingDays));

/// The latest imports of every service with a calendar.
final recentlyAddedProvider =
    NotifierProvider.autoDispose<
      CalendarReadNotifier<ImportedItem>,
      ServiceAnswers<ImportedItem>?
    >(_RecentlyAdded.new);

/// The problems every server reports.
final healthProvider =
    NotifierProvider.autoDispose<
      ServiceReadNotifier<HealthProvider, HealthIssue>,
      ServiceAnswers<HealthIssue>?
    >(_Health.new);

/// The disk space of every server that reports it.
final diskSpaceProvider =
    NotifierProvider.autoDispose<
      ServiceReadNotifier<HealthProvider, DiskSpace>,
      ServiceAnswers<DiskSpace>?
    >(_DiskSpace.new);

class _RecentlyAdded extends CalendarReadNotifier<ImportedItem> {
  @override
  ServiceResult<List<ImportedItem>> read(CalendarProvider provider) =>
      provider.recentlyAdded();
}

class _Health extends ServiceReadNotifier<HealthProvider, HealthIssue> {
  @override
  CapabilityKind<HealthProvider> get kind => CapabilityKind.health;

  @override
  ServiceResult<List<HealthIssue>> read(HealthProvider provider) =>
      provider.health();
}

class _DiskSpace extends ServiceReadNotifier<HealthProvider, DiskSpace> {
  @override
  CapabilityKind<HealthProvider> get kind => CapabilityKind.health;

  @override
  bool offers(HealthProvider provider) => provider.providesDiskSpace;

  @override
  ServiceResult<List<DiskSpace>> read(HealthProvider provider) =>
      provider.diskSpace();
}
