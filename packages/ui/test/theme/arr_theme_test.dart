import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

const black = Color(0xFF000000);

/// WCAG contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final first = a.computeLuminance() + 0.05;
  final second = b.computeLuminance() + 0.05;
  return first > second ? first / second : second / first;
}

void main() {
  final themes = {
    'light': (ArrTheme.light(), Brightness.light),
    'dark': (ArrTheme.dark(), Brightness.dark),
    'true black': (ArrTheme.dark(trueBlack: true), Brightness.dark),
  };

  for (final MapEntry(key: name, value: (theme, brightness))
      in themes.entries) {
    test('$name is a Material 3 theme with readable text', () {
      final scheme = theme.colorScheme;

      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, brightness);
      expect(
        contrast(scheme.onSurface, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  test('the dark background is not black unless asked for', () {
    expect(ArrTheme.dark().scaffoldBackgroundColor, isNot(black));
  });

  test('true black has a black background and visible raised surfaces', () {
    final theme = ArrTheme.dark(trueBlack: true);

    expect(theme.scaffoldBackgroundColor, black);
    expect(theme.colorScheme.surface, black);
    expect(theme.colorScheme.surfaceContainerLow, isNot(black));
    expect(theme.colorScheme.surfaceContainerHigh, isNot(black));
  });

  group('dynamic colour', () {
    const seed = Color(0xFFB3261E);
    final light = ColorScheme.fromSeed(seedColor: seed);
    final dark = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    test('replaces the colours of the app', () {
      expect(ArrTheme.light(dynamicScheme: light).colorScheme, light);
      expect(ArrTheme.dark(dynamicScheme: dark).colorScheme, dark);
      expect(ArrTheme.light().colorScheme.primary, isNot(light.primary));
    });

    test('keeps dark cards visible when surface is as light as them', () {
      // The shape dynamic_color builds: surface from an older, lighter tone.
      final scheme = dark.copyWith(surface: dark.surfaceContainerLow);

      final colors = ArrTheme.dark(dynamicScheme: scheme).colorScheme;

      expect(colors.surface, dark.surfaceDim);
      expect(colors.surface, isNot(colors.surfaceContainerLow));
      expect(colors.surfaceContainerLow, dark.surfaceContainerLow);
    });

    test('keeps its other colours on true black', () {
      final theme = ArrTheme.dark(dynamicScheme: dark, trueBlack: true);

      expect(theme.scaffoldBackgroundColor, black);
      expect(theme.colorScheme.primary, dark.primary);
      expect(theme.colorScheme.surfaceContainerHigh, dark.surfaceContainerHigh);
    });
  });
}
