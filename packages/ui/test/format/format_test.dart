import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../widgets/app.dart';

void main() {
  testWidgets('formats sizes and lengths of time', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    for (final (bytes, text) in [
      (0, '0 B'),
      (1023, '1,023 B'),
      (1024, '1.0 KiB'),
      (1536 * 1024, '1.5 MiB'),
      // Not 1,024.0 MiB.
      (1024 * 1024 * 1024 - 1, '1.0 GiB'),
      (5000 * 1024 * 1024 * 1024 * 1024, '5,000.0 TiB'),
    ]) {
      expect(formatBytes(context, bytes), text);
    }
    for (final (duration, text) in [
      (Duration.zero, 'under 1 min'),
      (const Duration(seconds: 59), 'under 1 min'),
      (const Duration(minutes: 5, seconds: 30), '5 min'),
      (const Duration(hours: 2, minutes: 5), '2 h 5 min'),
      (const Duration(days: 1, hours: 2, minutes: 8), '1 d 2 h'),
    ]) {
      expect(formatDuration(context, duration), text);
    }
    expect(formatSpeed(context, 0), '0 B/s');
    expect(formatSpeed(context, 1536 * 1024), '1.5 MiB/s');
  });
}
