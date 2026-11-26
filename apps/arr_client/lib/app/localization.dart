import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../src/l10n/generated/app_localizations.dart';
import 'modules.dart';

/// The strings of the app, of `ui` and its widgets, and of every module.
const List<LocalizationsDelegate<Object?>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...uiLocalizationsDelegates,
  ...moduleLocalizationsDelegates,
];
