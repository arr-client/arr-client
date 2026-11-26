import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../activity/queue/queue_controller.dart';
import '../calendar/calendar_data.dart';
import '../calendar/today.dart';
import 'home_data.dart';

/// Reads everything on Home again, and completes when every service has
/// answered. Only for use while Home is shown, as it reads what that watches.
Future<void> refreshHome(WidgetRef ref) =>
    Future.wait([ref.read(queueProvider.notifier).refresh(), reloadHome(ref)]);

/// As [refreshHome], without the queues, which are read by themselves.
Future<void> reloadHome(WidgetRef ref) {
  final today = ref.read(todayProvider);
  return Future.wait([
    ref.read(calendarEventsProvider(upcomingRange(today)).notifier).reload(),
    reloadImports(ref),
    ref.read(healthProvider.notifier).reload(),
    ref.read(diskSpaceProvider.notifier).reload(),
  ]);
}

/// Reads what was imported again, from every service or only from
/// [instanceId].
Future<void> reloadImports(WidgetRef ref, {String? instanceId}) => Future.wait([
  ref
      .read(importedOnProvider(ref.read(todayProvider)).notifier)
      .reload(instanceId: instanceId),
  ref.read(recentlyAddedProvider.notifier).reload(instanceId: instanceId),
]);
