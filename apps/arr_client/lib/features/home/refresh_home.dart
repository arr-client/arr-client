import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../activity/queue/queue_controller.dart';
import '../calendar/calendar_data.dart';
import '../calendar/today.dart';
import 'home_data.dart';

/// Reads everything on Home again, and completes when every service has
/// answered. Only for use while Home is shown, as it reads what that watches.
Future<void> refreshHome(WidgetRef ref) {
  final today = ref.read(todayProvider);
  return Future.wait([
    ref.read(calendarEventsProvider(upcomingRange(today)).notifier).reload(),
    ref.read(importedOnProvider(today).notifier).reload(),
    ref.read(recentlyAddedProvider.notifier).reload(),
    ref.read(queueProvider.notifier).refresh(),
    ref.read(healthProvider.notifier).reload(),
    ref.read(diskSpaceProvider.notifier).reload(),
  ]);
}
