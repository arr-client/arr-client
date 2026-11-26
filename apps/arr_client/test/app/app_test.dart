import 'dart:typed_data';

import 'package:arr_client/app/app.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

const deviceColor = Color(0xFFB3261E);

/// Answers the plugin as an Android 12 device would, with every one of the 65
/// palette entries (5 palettes of 13 tones) set to [deviceColor].
void useDevicePalette(WidgetTester tester) {
  final palette = Int32List.fromList(List.filled(65, deviceColor.toARGB32()));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    DynamicColorPlugin.channel,
    (call) async =>
        call.method == DynamicColorPlugin.methodName ? palette : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DynamicColorPlugin.channel,
      null,
    ),
  );
}

ThemeData themeOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold)));

void main() {
  testWidgets('the app starts on an empty screen', (tester) async {
    await tester.pumpWidget(const ArrClientApp());

    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('follows the system brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const ArrClientApp());

    expect(themeOf(tester).brightness, Brightness.dark);
  });

  testWidgets('a changed theme setting applies to the running app', (
    tester,
  ) async {
    await tester.pumpWidget(const ArrClientApp(themeMode: ThemeMode.light));
    expect(themeOf(tester).brightness, Brightness.light);

    await tester.pumpWidget(
      const ArrClientApp(themeMode: ThemeMode.dark, trueBlack: true),
    );
    await tester.pumpAndSettle();

    expect(themeOf(tester).brightness, Brightness.dark);
    expect(themeOf(tester).scaffoldBackgroundColor, const Color(0xFF000000));
  });

  testWidgets('uses the device colours only when dynamic colour is on', (
    tester,
  ) async {
    useDevicePalette(tester);
    final own = ArrTheme.light().colorScheme.primary;

    await tester.pumpWidget(const ArrClientApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
    expect(themeOf(tester).colorScheme.primary, own);

    await tester.pumpWidget(
      const ArrClientApp(themeMode: ThemeMode.light, dynamicColor: true),
    );
    await tester.pumpAndSettle();
    expect(themeOf(tester).colorScheme.primary, deviceColor);
  });

  testWidgets('keeps its own colours on a device without dynamic colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ArrClientApp(themeMode: ThemeMode.light, dynamicColor: true),
    );
    await tester.pumpAndSettle();

    expect(
      themeOf(tester).colorScheme.primary,
      ArrTheme.light().colorScheme.primary,
    );
  });

  testWidgets('screens can read the localized strings', (tester) async {
    await tester.pumpWidget(const ArrClientApp());
    final context = tester.element(find.byType(Scaffold));

    expect(UiLocalizations.of(context).cancel, 'Cancel');
  });
}
