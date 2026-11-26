import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('provides the strings of ui and of the Material widgets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: uiLocalizationsDelegates,
        supportedLocales: UiLocalizations.supportedLocales,
        home: Scaffold(),
      ),
    );
    final context = tester.element(find.byType(Scaffold));

    expect(UiLocalizations.of(context).cancel, 'Cancel');
    expect(UiLocalizations.of(context).retry, 'Retry');
    // Not DefaultMaterialLocalizations, which only knows English.
    expect(
      MaterialLocalizations.of(context),
      isA<GlobalMaterialLocalizations>(),
    );
  });
}
