import 'package:arr_client/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the app starts on an empty screen', (tester) async {
    await tester.pumpWidget(const ArrClientApp());

    expect(find.byType(Scaffold), findsOneWidget);
  });
}
