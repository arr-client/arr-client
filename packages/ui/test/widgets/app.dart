import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

/// [body] in a themed, localized app, as a screen would have it.
Widget testApp(Widget body, {double textScale = 1}) => MaterialApp(
  theme: ArrTheme.light(),
  localizationsDelegates: uiLocalizationsDelegates,
  supportedLocales: UiLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: body),
);

/// A small phone.
void useSmallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Fails unless every control on screen has a label and a 48 dp target.
Future<void> expectAccessibleTargets(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}
