import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'wanted_controller.dart';
import 'wanted_view.dart';

/// What the active profile's services are still looking for: what is missing
/// and what is below its quality cutoff, with searches for them.
class WantedScreen extends ConsumerWidget {
  const WantedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return DefaultTabController(
      length: WantedKind.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.moreWanted),
          actions: [
            // Pulling down does this too, which a screen reader cannot.
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: strings.wantedRefresh,
                onPressed: () {
                  final kind =
                      WantedKind.values[DefaultTabController.of(context).index];
                  unawaited(ref.read(wantedProvider(kind).notifier).reload());
                },
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: strings.wantedTabMissing),
              Tab(text: strings.wantedTabCutoff),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final kind in WantedKind.values) WantedView(kind: kind),
          ],
        ),
      ),
    );
  }
}
