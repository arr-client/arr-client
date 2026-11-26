import 'package:arr_client/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('t007 probe second: the app starts', (tester) async {
    app.main();
    await tester.pumpAndSettle();
  });
}
