/// Settings: theme, diagnostic log and licenses (spec story 13, scenarios 4
/// and 5).
library;

import 'dart:convert';
import 'dart:io';

import 'package:arr_client/app/platform/text_sharer.dart';
import 'package:arr_client/features/settings/diagnostics/diagnostic_log_screen.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation_test.dart' show open, usePhone;
import '../../app/support.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<TestApp> _settings(WidgetTester tester) async {
  usePhone(tester);
  final app = await TestApp.start(tester);
  await app.pump(tester);
  await open(tester, 'More');
  await _tap(tester, find.text('Settings'));
  return app;
}

/// Opens an entry of Settings, which large text can push out of sight.
Future<void> _entry(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.text(name));
  await tester.pumpAndSettle();
  await _tap(tester, find.text(name));
}

ThemeMode? _themeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;

/// All the text on screen.
String _onScreen(WidgetTester tester) =>
    [for (final text in tester.widgetList<Text>(find.byType(Text))) text.data]
        .join('\n');

void main() {
  testWidgets('the chosen theme is applied at once and kept', (tester) async {
    final app = await _settings(tester);
    expect(_themeMode(tester), ThemeMode.system);

    await _tap(tester, find.text('Dark'));

    expect(_themeMode(tester), ThemeMode.dark);
    expect(
      (await app.services.preferences.read()).themeMode,
      AppThemeMode.dark,
    );

    await _tap(tester, find.text('Light'));
    expect(_themeMode(tester), ThemeMode.light);

    await _tap(tester, find.text('Follow system'));
    expect(_themeMode(tester), ThemeMode.system);
    await app.stop(tester);
  });

  testWidgets('what the log shows is what is shared, without secrets', (
    tester,
  ) async {
    final app = await _settings(tester);
    // Saving the instance registers its credential with the log.
    await app.add(movies, 'Films');
    app.services.log.log(
      LogLevel.error,
      'The key zq-key-0123456789 was refused',
      error: 'password=hunter22 at https://u:pw-seed@nas/api?apikey=qs-seed',
    );
    await tester.pumpAndSettle();

    await _entry(tester, 'Diagnostic log');

    final shown = _onScreen(tester);
    expect(shown, contains('was refused'));
    expect(shown, contains('Share log sends the entries below'));
    expect(app.sharer.shared, isEmpty, reason: 'only the user shares');

    // Logged after the log was read, so neither shown nor shared.
    app.services.log.log(LogLevel.info, 'a later entry');
    await _tap(tester, find.text('Share log'));

    final shared = app.sharer.shared.single;
    expect(shared, contains(SecretRedactor.marker));
    expect(shared, isNot(contains('a later entry')));
    for (final line in shared.split('\n')) {
      expect(shown, contains(line));
    }
    for (final secret in ['zq-key', 'hunter22', 'pw-seed', 'qs-seed']) {
      expect(shown, isNot(contains(secret)));
      expect(shared, isNot(contains(secret)));
    }

    await _tap(tester, find.byTooltip('Refresh log'));
    expect(find.textContaining('a later entry'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('an empty log offers nothing to share', (tester) async {
    final app = await _settings(tester);
    app.services.log.clear();

    await _entry(tester, 'Diagnostic log');

    expect(
      find.text('Nothing has been logged since the app started.'),
      findsOneWidget,
    );
    expect(find.text('Share log'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('a long log is cut to its newest entries', (tester) async {
    final app = await _settings(tester);
    app.services.log.clear();
    for (var i = 0; i < 40; i++) {
      app.services.log.log(LogLevel.info, 'entry-$i ${'x ' * 1900}');
    }

    await _entry(tester, 'Diagnostic log');
    expect(find.textContaining('Older entries are left out'), findsOneWidget);
    await _tap(tester, find.text('Share log'));

    final shared = app.sharer.shared.single;
    expect(shared.length, lessThanOrEqualTo(DiagnosticLogScreen.shareLimit));
    expect(shared, contains('entry-39 '));
    expect(shared, isNot(contains('entry-0 ')));
    await app.stop(tester);
  });

  testWidgets('a share sheet that does not open is reported', (tester) async {
    final app = await _settings(tester);
    app.services.log.log(LogLevel.info, 'something');
    app.sharer.failure = PlatformException(code: 'seeded');

    await _entry(tester, 'Diagnostic log');
    await _tap(tester, find.text('Share log'));

    expect(
      find.text('The log could not be shared. Try again.'),
      findsOneWidget,
    );
    expect(
      app.services.log.entries.last.message,
      'The log could not be shared (PlatformException)',
    );
    await app.stop(tester);
  });

  testWidgets('the licenses carry the notice of the app and its packages', (
    tester,
  ) async {
    final app = await _settings(tester);

    await _entry(tester, 'Licenses');
    await tester.pumpAndSettle();

    expect(find.text('arr-client'), findsOneWidget);
    expect(find.textContaining('no warranty'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('settings and the log work with large text', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await _settings(tester);
    app.services.log.log(LogLevel.info, 'something');

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await _entry(tester, 'Diagnostic log');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await _tap(tester, find.text('Share log'));

    expect(app.sharer.shared, hasLength(1));
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await app.stop(tester);
  });

  test('sharing asks the platform for the share sheet', () async {
    final messenger =
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(SystemTextSharer.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemTextSharer.channel, null),
    );

    await const SystemTextSharer().share('the log');

    expect(calls.single.method, 'shareText');
    expect(calls.single.arguments, 'the log');
  });

  test("the project's license is bundled where the notice says", () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The test binding shows no licenses, so this reads what a build bundles.
    final bundled = await rootBundle.load('NOTICES.Z');
    final notices = utf8.decode(gzip.decode(Uint8List.sublistView(bundled)));

    expect(
      notices,
      matches(r'arr_client_workspace\n\n\s*GNU GENERAL PUBLIC LICENSE'),
    );
  });
}
