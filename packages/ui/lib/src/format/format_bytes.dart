import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/ui_localizations.dart';

/// A transfer speed in bytes per second, with the size as [formatBytes] writes
/// it. [context] must be below the app's localizations.
String formatSpeed(BuildContext context, int bytesPerSecond) =>
    UiLocalizations.of(context)
        .speedPerSecond(formatBytes(context, bytesPerSecond));

/// A size in bytes, in the largest binary unit it has one of, with the viewer's
/// number format. [context] must be below the app's localizations.
String formatBytes(BuildContext context, int bytes) {
  final l10n = UiLocalizations.of(context);
  var value = bytes.toDouble();
  var unit = 0;
  // From 1023.95 on, a value would be shown as 1,024.0 of the smaller unit.
  while (value >= 1023.95 && unit < 4) {
    value /= 1024;
    unit++;
  }
  final number = NumberFormat.decimalPatternDigits(
    locale: Localizations.localeOf(context).toString(),
    decimalDigits: unit == 0 ? 0 : 1,
  ).format(value);
  return switch (unit) {
    0 => l10n.sizeBytes(number),
    1 => l10n.sizeKibibytes(number),
    2 => l10n.sizeMebibytes(number),
    3 => l10n.sizeGibibytes(number),
    _ => l10n.sizeTebibytes(number),
  };
}
