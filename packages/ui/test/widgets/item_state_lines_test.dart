import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'app.dart';

void main() {
  testWidgets('says each state, and monitoring, in words', (tester) async {
    await tester.pumpWidget(
      testApp(
        ListView(
          children: [
            for (final state in ItemState.values) ItemStateLine(state),
            const MonitoredLine(monitored: true),
            const MonitoredLine(monitored: false),
          ],
        ),
      ),
    );

    for (final word in [
      'Downloading',
      'Downloaded',
      'Partly downloaded',
      'Unmonitored',
      'Unreleased',
      'Missing',
      'Monitored',
      'Not monitored',
    ]) {
      expect(find.text(word), findsOneWidget, reason: word);
    }
  });

  testWidgets('lists each fact as one thing for a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const FactList([('Studio', 'Harbour')])));

    expect(find.bySemanticsLabel('Studio\nHarbour'), findsOneWidget);
    semantics.dispose();
  });
}
