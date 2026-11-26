import 'package:material_ui/material_ui.dart';

/// Colour the schemes are generated from when dynamic colour is not used.
const Color _seedColor = Color(0xFF006A6A);

const Color _black = Color(0xFF000000);

/// The Material 3 themes of the app.
///
/// For dynamic colour, pass the scheme the device provides. Pass null when the
/// user has it turned off or the device has none; the app's own colours are
/// used then.
abstract final class ArrTheme {
  /// The light theme. [dynamicScheme] must be a light scheme.
  static ThemeData light({ColorScheme? dynamicScheme}) {
    assert(dynamicScheme?.brightness != Brightness.dark);
    return ThemeData(
      colorScheme: dynamicScheme ?? ColorScheme.fromSeed(seedColor: _seedColor),
    );
  }

  /// The dark theme. [dynamicScheme] must be a dark scheme.
  ///
  /// With [trueBlack] the background is pure black, while raised surfaces such
  /// as cards and menus stay distinguishable from it.
  static ThemeData dark({ColorScheme? dynamicScheme, bool trueBlack = false}) {
    assert(dynamicScheme?.brightness != Brightness.light);
    final scheme =
        dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        );
    return ThemeData(
      colorScheme: trueBlack
          ? scheme.copyWith(
              surface: _black,
              surfaceDim: _black,
              surfaceContainerLowest: _black,
            )
          // In a dark Material 3 scheme surface and surfaceDim are the same
          // colour. The schemes of dynamic_color break that: their surface is
          // as light as surfaceContainerLow, which hides cards.
          : scheme.copyWith(surface: scheme.surfaceDim),
    );
  }
}
