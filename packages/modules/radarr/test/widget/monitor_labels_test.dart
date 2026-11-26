// The names of the monitoring options come from the module's localizations.

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import '../contract/library_support.dart';
import '../contract/lookup_support.dart';

void main() {
  testWidgets('each monitoring option has its name', (tester) async {
    final options = await succeed(
      LookupHarness().lookup.addOptions(MediaKind.movie),
    );
    late List<String> names;

    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: const [
          RadarrLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Builder(
          builder: (context) {
            names = [
              for (final option in options.monitorOptions)
                option.label(context),
            ];
            return const SizedBox();
          },
        ),
      ),
    );

    expect(names, ['Movie only', 'Movie and collection', 'None']);
  });
}
