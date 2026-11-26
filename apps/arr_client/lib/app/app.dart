import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

/// Root widget of the app shell.
class ArrClientApp extends StatelessWidget {
  const ArrClientApp({
    super.key,
    this.themeMode = ThemeMode.system,
    this.trueBlack = false,
    this.dynamicColor = false,
  });

  /// Light, dark or following the system.
  final ThemeMode themeMode;

  /// Whether the dark theme has a pure black background.
  final bool trueBlack;

  /// Whether to take colours from the device, where it provides them.
  final bool dynamicColor;

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (lightScheme, darkScheme) => MaterialApp(
      theme: ArrTheme.light(dynamicScheme: dynamicColor ? lightScheme : null),
      darkTheme: ArrTheme.dark(
        dynamicScheme: dynamicColor ? darkScheme : null,
        trueBlack: trueBlack,
      ),
      themeMode: themeMode,
      localizationsDelegates: uiLocalizationsDelegates,
      supportedLocales: UiLocalizations.supportedLocales,
      home: const Scaffold(),
    ),
  );
}
