import 'package:material_ui/material_ui.dart';

import 'generated/ui_localizations.dart';

/// Delegates for the strings of `ui` and of the Material, Cupertino and basic
/// widgets. A package with strings of its own adds its delegate to these.
///
/// Use these instead of `UiLocalizations.localizationsDelegates`: the generated
/// list translates the deprecated `package:flutter/material.dart` widgets, not
/// those of `material_ui`.
const List<LocalizationsDelegate<Object?>> uiLocalizationsDelegates = [
  UiLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
