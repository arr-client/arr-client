import 'dart:typed_data';

import 'package:arr_client/app/bootstrap.dart';
import 'package:arr_client/app/composition.dart';
import 'package:core/core.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'support.dart';

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

BuildContext screenOf(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first);

ThemeData themeOf(WidgetTester tester) => Theme.of(screenOf(tester));

void main() {
  testWidgets('follows the system brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final app = await TestApp.start(tester);

    await app.pump(tester);

    expect(themeOf(tester).brightness, Brightness.dark);
    await app.stop(tester);
  });

  testWidgets('a changed theme setting applies to the running app', (
    tester,
  ) async {
    final app = await TestApp.start(tester);
    await app.services.preferences.setThemeMode(AppThemeMode.light);
    await app.pump(tester);
    expect(themeOf(tester).brightness, Brightness.light);

    await app.services.preferences.setThemeMode(AppThemeMode.dark);
    await app.services.preferences.setTrueBlack(true);
    await tester.pumpAndSettle();

    expect(themeOf(tester).brightness, Brightness.dark);
    expect(themeOf(tester).scaffoldBackgroundColor, const Color(0xFF000000));
    await app.stop(tester);
  });

  testWidgets('uses the device colours only while dynamic colour is on', (
    tester,
  ) async {
    useDevicePalette(tester);
    final app = await TestApp.start(tester);
    await app.services.preferences.setThemeMode(AppThemeMode.light);
    await app.pump(tester);
    expect(themeOf(tester).colorScheme.primary, deviceColor);

    await app.services.preferences.setDynamicColor(false);
    await tester.pumpAndSettle();

    expect(
      themeOf(tester).colorScheme.primary,
      ArrTheme.light().colorScheme.primary,
    );
    await app.stop(tester);
  });

  testWidgets('creates a first profile and shows its name', (tester) async {
    final app = await TestApp.start(tester);

    await app.pump(tester);

    expect(find.widgetWithText(AppBar, 'Default'), findsOneWidget);
    expect(UiLocalizations.of(screenOf(tester)).cancel, 'Cancel');
    await app.stop(tester);
  });

  testWidgets('resuming applies what was saved meanwhile', (tester) async {
    final app = await TestApp.start(tester);
    await app.add(movies, 'Films');
    await app.pump(tester);
    expect(find.text('Library'), findsOneWidget);
    // Behind the back of the database's change notifications, as another
    // isolate would write.
    await app.services.database.customStatement(
      'UPDATE instances SET enabled = 0',
    );
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);

    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('a failed start says so and can be tried again', (tester) async {
    TestApp? app;
    var attempts = 0;
    Future<AppServices> start() async {
      if (attempts++ == 0) throw StateError('no storage');
      return (app = await TestApp.start(tester)).services;
    }

    await tester.pumpWidget(Bootstrap(start: start));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not open its data'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Default'), findsOneWidget);
    // The bootstrap closes what it started when it is taken down.
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    expect(app, isNotNull);
  });
}
