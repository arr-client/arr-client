// The names of what can be monitored.

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarr/sonarr_module.dart';

import '../contract/support.dart';

void main() {
  testWidgets('every monitoring option has a name of its own', (tester) async {
    final options = await ok(Harness().lookup.addOptions(MediaKind.series));
    late BuildContext context;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: const [
          SonarrLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Builder(
          builder: (found) {
            context = found;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final names = {
      for (final option in options.monitorOptions)
        option.id: option.label(context),
    };

    expect(names['all'], 'All episodes');
    expect(names['firstSeason'], 'First season');
    expect(names['none'], 'None');
    expect(names.values, everyElement(isNotEmpty));
    expect(names.values.toSet(), hasLength(names.length));
  });
}
