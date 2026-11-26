import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/prowlarr_localizations.dart';
import 'grab_result.dart';
import 'indexers_tab.dart';
import 'prowlarr_source.dart';
import 'search_controller.dart';
import 'search_tab.dart';

/// Indexer search, grab and read-only indexer status: spec story 11.
///
/// It must be below a Riverpod `ProviderScope`.
class IndexerScreen extends ConsumerStatefulWidget {
  /// Creates the screen of [source], for the instance called [name].
  const IndexerScreen({required this.source, required this.name, super.key});

  /// Where it reads from.
  final ProwlarrSource source;

  /// The instance's name.
  final String name;

  @override
  ConsumerState<IndexerScreen> createState() => _IndexerScreenState();
}

class _IndexerScreenState extends ConsumerState<IndexerScreen> {
  // Kept while the screen is, over both tabs.
  final _term = TextEditingController();
  final _filters = ValueNotifier(const SearchFilters());
  final ValueNotifier<ResultOrder> _order = ValueNotifier((
    sort: ReleaseSort.server,
    ascending: true,
  ));

  @override
  void dispose() {
    _term.dispose();
    _filters.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ProwlarrLocalizations.of(context);
    // The results are kept while the other tab is shown.
    ref.listen(searchProvider(widget.source), (_, _) {});
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.name),
          bottom: TabBar(
            tabs: [
              Tab(text: strings.searchTab),
              Tab(text: strings.indexersTab),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(
            children: [
              SearchTab(
                source: widget.source,
                term: _term,
                filters: _filters,
                order: _order,
                // The screen's context, which outlives the rows.
                onGrab: (release) => unawaited(
                  grabResult(context, ref, widget.source, widget.name, release),
                ),
              ),
              IndexersTab(source: widget.source),
            ],
          ),
        ),
      ),
    );
  }
}
