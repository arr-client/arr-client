import 'package:flutter/widgets.dart';

import '../l10n/generated/ui_localizations.dart';

/// A length of time in its two largest units, such as days and hours. [context]
/// must be below the app's localizations.
String formatDuration(BuildContext context, Duration duration) {
  final l10n = UiLocalizations.of(context);
  if (duration.inDays > 0) {
    return l10n.durationDaysHours(duration.inDays, duration.inHours % 24);
  }
  if (duration.inHours > 0) {
    return l10n.durationHoursMinutes(duration.inHours, duration.inMinutes % 60);
  }
  if (duration.inMinutes > 0) return l10n.durationMinutes(duration.inMinutes);
  return l10n.durationUnderAMinute;
}
