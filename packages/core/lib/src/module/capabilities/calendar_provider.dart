import '../../models/calendar_event.dart';
import '../../models/imported_item.dart';
import '../capability.dart';
import '../service_result.dart';

/// Upcoming releases and recent imports.
abstract interface class CalendarProvider implements Capability {
  ServiceResult<List<CalendarEvent>> events(DateTime from, DateTime to);

  /// The latest imports, grouped by item.
  ServiceResult<List<ImportedItem>> recentlyAdded();

  /// What was imported on the device's local [day], grouped by item.
  ServiceResult<List<ImportedItem>> importedOn(DateTime day);
}
