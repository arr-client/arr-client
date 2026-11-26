/// How the app writes dates and times, in the viewer's locale and the device's
/// time zone.
library;

import 'package:material_ui/material_ui.dart';

/// The day [date] falls on, with its weekday.
///
/// [context] must be below the app's localizations.
String formatDay(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatFullDate(date.toLocal());

/// The time of day of [instant], in the 12 or 24 hour form the device is set to.
///
/// [context] must be below the app's localizations.
String formatTime(BuildContext context, DateTime instant) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(instant.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
