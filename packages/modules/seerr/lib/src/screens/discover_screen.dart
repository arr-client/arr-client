import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/seerr_localizations.dart';
import '../routes.dart';
import 'discover_controller.dart';
import 'labels.dart';
import 'seerr_source.dart';
import 'title_parts.dart';

/// Browsing and searching one instance's titles: spec story 9.
///
/// It must be below a Riverpod `ProviderScope`.
class DiscoverScreen extends ConsumerStatefulWidget {
  /// Creates the screen of [source], for the instance called [name].
  const DiscoverScreen({
    required this.source,
    required this.name,
    required this.offersQuota,
    super.key,
  });

  /// Where it reads from.
  final SeerrSource source;

  /// The instance's name.
  final String name;

  /// Whether the user may request anything, and so has a quota to see.
  final bool offersQuota;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _term = TextEditingController();

  @override
  void dispose() {
    _term.dispose();
    super.dispose();
  }

  DiscoverController get _controller =>
      ref.read(discoverProvider(widget.source).notifier);

  void _search() {
    unawaited(
      _controller.show((
        category: ref.read(discoverProvider(widget.source)).query.category,
        term: _term.text.trim(),
      )),
    );
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    _search();
  }

  void _browse(DiscoveryCategory category) {
    FocusManager.instance.primaryFocus?.unfocus();
    _term.clear();
    unawaited(_controller.show((category: category, term: '')));
  }

  @override
  Widget build(BuildContext context) {
    final strings = SeerrLocalizations.of(context);
    final state = ref.watch(discoverProvider(widget.source));
    Future<void> refresh() => _controller.refresh();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          // Pulling down does this too, which a screen reader cannot.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.refresh,
            onPressed: () => unawaited(refresh()),
          ),
          if (widget.offersQuota)
            IconButton(
              icon: const Icon(Icons.data_usage),
              tooltip: strings.quotaTitle,
              onPressed: () => unawaited(
                context.push<void>(
                  ModuleRoute(
                    instanceId: widget.source.instanceId,
                    path: quotaPattern,
                  ).location,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final margin = screenMargin(constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(margin, 8, margin, 0),
                  child: TextField(
                    controller: _term,
                    onSubmitted: (_) => _submit(),
                    // Emptied, the lists come back.
                    onChanged: (term) {
                      if (term.isEmpty) _search();
                    },
                    textInputAction: TextInputAction.search,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                      labelText: strings.searchLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: strings.searchSubmit,
                        onPressed: _submit,
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                    horizontal: margin,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      for (final category in DiscoveryCategory.values)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(categoryLabel(strings, category)),
                            selected:
                                state.query.term.isEmpty &&
                                state.query.category == category,
                            onSelected: (_) => _browse(category),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: refresh,
                    child: _content(context, state),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, DiscoverState state) {
    final strings = SeerrLocalizations.of(context);
    final items = state.items;
    final fetchedAt = state.fetchedAt;
    final failure = state.failure;
    return StateScaffold<DiscoverState>(
      state: items != null && fetchedAt != null
          ? ViewData(
              state,
              staleness: state.loading || failure != null
                  ? Staleness(fetchedAt: fetchedAt, failure: failure)
                  : null,
            )
          : failure != null && !state.loading
          ? ViewError(failure)
          : const ViewLoading(),
      onRetry: () => unawaited(_controller.refresh()),
      // A page can hold no title and still have others after it.
      isEmpty: (state) => state.items!.isEmpty && !state.hasMore,
      emptyMessage: state.query.term.isEmpty
          ? strings.browseEmpty
          : strings.searchNone,
      builder: (context, state, {required isStale}) => LayoutBuilder(
        // Kept over a visit to a title; another list starts at the top.
        key: PageStorageKey(state.listing),
        builder: (context, constraints) {
          final titles = state.items!;
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: screenMargin(constraints.maxWidth),
              vertical: 8,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: titles.length + (state.hasMore ? 1 : 0),
            itemBuilder: (context, index) => index == titles.length
                ? _more(context, state)
                : _TitleRow(source: widget.source, title: titles[index]),
          );
        },
      ),
    );
  }

  Widget _more(BuildContext context, DiscoverState state) {
    final strings = SeerrLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (state.moreFailure case final failure?)
            Semantics(
              liveRegion: true,
              child: Text(failureMessage(context, failure)),
            ),
          if (state.loadingMore)
            CircularProgressIndicator(
              semanticsLabel: UiLocalizations.of(context).loading,
            )
          else
            TextButton(
              onPressed: state.loading
                  ? null
                  : () => unawaited(_controller.more()),
              child: Text(strings.loadMore),
            ),
        ],
      ),
    );
  }
}

/// A title in a list. A list says nothing about requests, which the title's
/// own screen reads; what is known from there is shown.
class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.source, required this.title});

  final SeerrSource source;
  final DiscoveryTitle title;

  @override
  Widget build(BuildContext context) {
    final strings = SeerrLocalizations.of(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => unawaited(
        context.push<void>(source.discovery.detailRoute(title).location),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TitlePoster(title: title, artwork: source.artwork, width: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.title, style: theme.textTheme.titleMedium),
                    Text(
                      titleFacts(strings, title),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    IconLine(
                      availabilityIcon(title.availability),
                      availabilityLabel(strings, title.availability),
                    ),
                    if (requestStatusLabel(strings, title.requestStatus)
                        case final status?)
                      IconLine(Icons.assignment_outlined, status),
                    if (title.availability4k != Availability.unknown)
                      IconLine(
                        availabilityIcon(title.availability4k),
                        strings.in4k(
                          availabilityLabel(strings, title.availability4k),
                        ),
                      ),
                    if (requestStatusLabel(strings, title.requestStatus4k)
                        case final status?)
                      IconLine(Icons.assignment_outlined, strings.in4k(status)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
