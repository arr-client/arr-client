import 'package:material_ui/material_ui.dart';

import 'app/bootstrap.dart';
import 'app/composition.dart';

void main() {
  // The device's services are reached over platform channels.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap(start: startOnDevice));
}
