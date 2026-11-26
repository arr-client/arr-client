import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/navigation/locations.dart';
import '../../src/l10n/generated/app_localizations.dart';
import 'library_controller.dart';
import 'library_entry.dart';
import 'library_filter_sheet.dart';
import 'library_notices.dart';
import 'library_query.dart';
import 'library_state.dart';
import 'library_tiles.dart';
import 'library_toolbar.dart';
import 'manage/search_progress.dart';
import 'manage/selection_actions.dart';
import 'manage/selection_bar.dart';

/// The least width of a poster at the normal text size.
const _posterWidth = 104.0;

const _gridSpacing = 8.0;

/// The library of one kind: its toolbar, and the items as a grid or a list.
class LibraryViewBody extends ConsumerStatefulWidget {
  const LibraryViewBody({required this.kind, super.key});

  /// The kind of the top-level items shown.
  final MediaKind kind;

  @override
  ConsumerState<LibraryViewBody> createState() => _LibraryViewBodyState();
}

class _LibraryViewBodyState extends ConsumerState<LibraryViewBody> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final AppLifecycleListener _lifecycle;

  /// Whether the library is on screen, not behind another tab or page.
  var _onScreen = false;

  /// The items selected, all of one instance; null while not selecting.
  Set<ItemRef>? _selected;

  /// Whether a change of the selection is being sent.
  var _sending = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_onScreen) _refreshIfOld();
      },
    );
    ref.listenManual(libraryProvider(widget.kind), (previous, next) {
      final view = next.view;
      if (view == null) return;
      // Loaded, or cleared elsewhere; what is typed already matches.
      if (_text.text != view.filters.text) _text.text = view.filters.text;
      // Another order or other items: from the top.
      final before = previous?.view;
      if (before != null && before != view && _scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    }, fireImmediately: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tickers are off behind another destination or page.
    final onScreen = TickerMode.valuesOf(context).enabled;
    if (onScreen && !_onScreen) _refreshIfOld();
    _onScreen = onScreen;
  }

  void _refreshIfOld() {
    // Not during build, which must not set the state.
    scheduleMicrotask(() {
      if (mounted) unawaited(_controller.refreshIfOld());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  LibraryController get _controller =>
      ref.read(libraryProvider(widget.kind).notifier);

  void _select(Set<ItemRef>? selected) => setState(() => _selected = selected);

  void _toggle(ItemRef item) {
    final selected = {...?_selected};
    if (!selected.remove(item)) selected.add(item);
    _select(selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider(widget.kind));
    return StateScaffold<LibraryState>(
      state: _viewState(state),
      onRetry: () => unawaited(_controller.refresh()),
      builder: (context, state, {required isStale}) => _content(state),
    );
  }

  /// With several instances the screen is there as soon as the view is read:
  /// the choice between them must stay while the one chosen is still loading,
  /// and each says for itself how it is doing. A library of one instance has
  /// nothing but its loading or its failure until it has items.
  static ViewState<LibraryState> _viewState(LibraryState state) {
    if (state.view == null || state.sources.isEmpty) return const ViewLoading();
    if (state.sources.length > 1) return ViewData(state);
    final source = state.sources.single;
    if (source.entries != null) return ViewData(state);
    // A retry under way shows as loading.
    final failure = source.isLoading ? null : source.failure;
    return failure == null ? const ViewLoading() : ViewError(failure);
  }

  Widget _content(LibraryState state) {
    final view = state.view!;
    final strings = AppLocalizations.of(context);
    // Fresh data being asked for again says so only here; saved data has its
    // notice.
    final refreshing = state.shown.any(
      (source) => source.isLoading && source.fetchedAt == null,
    );
    // What is no longer shown is no longer selected.
    final selected = _selected?.intersection({
      for (final entry in state.visible) entry.item.ref,
    });
    Widget column(double height) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // In the toolbar's place, so that the filters cannot hide what is
        // selected.
        if (selected != null)
          _selectionBar(state, selected)
        else
          LibraryToolbar(
            view: view,
            text: _text,
            activeFilters: activeFilterCount(state),
            onText: _controller.setText,
            onSort: _controller.setSort,
            onFilters: () =>
                unawaited(showLibraryFilters(context, widget.kind)),
            onLayout: _controller.setLayout,
            onSelect: state.visible.isEmpty ? null : () => _select({}),
          ),
        // Takes its height either way, so that nothing moves.
        SizedBox(
          height: 4,
          child: refreshing
              ? LinearProgressIndicator(
                  semanticsLabel: strings.libraryRefreshing,
                )
              : null,
        ),
        // Above the items, not among them: in sight however far they are
        // scrolled, and leaving them room.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * 0.4),
          child: SingleChildScrollView(
            // The items are the screen's primary scroll view.
            primary: false,
            child: SearchProgress(
              kind: widget.kind,
              instanceIds: {for (final source in state.shown) source.id},
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _controller.refresh,
            child: Scrollbar(
              controller: _scroll,
              interactive: true,
              child: CustomScrollView(
                key: PageStorageKey('library ${widget.kind.name}'),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (state.sources.length > 1 && selected == null)
                    SliverToBoxAdapter(child: _scopes(state)),
                  SliverToBoxAdapter(
                    child: LibraryNotices(
                      state: state,
                      onRetry: (id) => unawaited(_controller.retry(id)),
                    ),
                  ),
                  _items(state, selected),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    // Back leaves the selection before it leaves the screen.
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(null);
      },
      child: LayoutBuilder(
        builder: (context, constraints) => column(constraints.maxHeight),
      ),
    );
  }

  Widget _selectionBar(LibraryState state, Set<ItemRef> selected) {
    final strings = AppLocalizations.of(context);
    final source = selected.isEmpty
        ? null
        : state.source(selected.first.instanceId);
    final items = [
      for (final entry in state.visible)
        if (selected.contains(entry.item.ref)) entry.item,
    ];
    // Nothing is changed on the strength of saved data.
    final stale =
        source != null && (source.fetchedAt != null || source.failure != null);
    final actionable = source != null && !stale && !_sending;
    return SelectionBar(
      count: items.length,
      instanceName: state.shown.length > 1 ? source?.name : null,
      note: stale
          ? strings.selectionStale(source.name)
          : state.shown.length > 1
          ? strings.selectionOneService
          : null,
      onCancel: () => _select(null),
      showSearch:
          source == null ||
          source.active.capability(CapabilityKind.command) != null,
      onSearch: actionable
          ? () => unawaited(
              searchSelection(
                context,
                ref,
                source.active,
                items,
                onStarted: () {
                  if (mounted) _select(null);
                },
              ),
            )
          : null,
      onEdit: actionable
          ? () => unawaited(
              editSelection(
                context,
                ref,
                source,
                items,
                onSending: () {
                  if (mounted) setState(() => _sending = true);
                },
                // Kept where it failed, to be looked at and tried again.
                onSent: (accepted) {
                  if (!mounted) return;
                  setState(() {
                    _sending = false;
                    if (accepted) _selected = null;
                  });
                },
              ),
            )
          : null,
    );
  }

  /// The choice between all instances and one.
  Widget _scopes(LibraryState state) {
    final strings = AppLocalizations.of(context);
    final scope = state.scopeId;
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: screenMargin(constraints.maxWidth),
        ),
        child: Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(strings.libraryAllServices),
              selected: scope == null,
              onSelected: (_) => _controller.setScope(null),
            ),
            for (final source in state.sources)
              ChoiceChip(
                label: Text(source.name),
                selected: scope == source.id,
                onSelected: (_) => _controller.setScope(source.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _items(LibraryState state, Set<ItemRef>? selected) {
    final entries = state.visible;
    if (entries.isEmpty) {
      // Items there are, and the filters hide them all.
      if (state.total > 0) {
        final strings = AppLocalizations.of(context);
        return SliverFillRemaining(
          child: StateMessage(
            icon: Icons.filter_list_off,
            message: strings.libraryNoMatch,
            announce: true,
            action: FilledButton(
              onPressed: _controller.clearFilters,
              child: Text(strings.libraryClearFilters),
            ),
          ),
        );
      }
      // Empty only if the servers just said so; otherwise the notices above
      // tell what there is to know.
      if (state.shown.any(
        (source) =>
            source.entries == null ||
            source.fetchedAt != null ||
            source.failure != null,
      )) {
        return const SliverToBoxAdapter();
      }
      final strings = AppLocalizations.of(context);
      return SliverFillRemaining(
        child: StateMessage(
          icon: Icons.inbox_outlined,
          message: switch (widget.kind) {
            MediaKind.series => strings.libraryNoSeries,
            MediaKind.artist => strings.libraryNoArtists,
            MediaKind.author => strings.libraryNoAuthors,
            _ => strings.libraryNoMovies,
          },
        ),
      );
    }
    final showsInstance = state.shown.length > 1;
    final names = {for (final source in state.shown) source.id: source.name};
    final artwork = {
      for (final source in state.shown)
        source.id: source.active.context.artwork,
    };
    // Places by item, so that a tile keeps its poster when others come or go.
    Key keyOf(LibraryEntry entry) => ValueKey(entry.item.ref);

    // The first one chosen decides the instance.
    final lockedTo = selected == null || selected.isEmpty
        ? null
        : selected.first.instanceId;
    bool? marked(LibraryEntry entry) => selected?.contains(entry.item.ref);
    VoidCallback? tap(LibraryEntry entry) {
      if (selected == null) return () => _open(state, entry);
      if (lockedTo != null && lockedTo != entry.instanceId) return null;
      return () => _toggle(entry.item.ref);
    }

    VoidCallback? longPress(LibraryEntry entry) =>
        selected == null ? () => _toggle(entry.item.ref) : null;

    final view = state.view!;
    if (view.layout == LibraryLayout.list) {
      final field = LibrarySortField.of(view.sort.field);
      return SliverFixedExtentList.builder(
        itemExtent: LibraryListTile.height(context),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return LibraryListTile(
            key: keyOf(entry),
            entry: entry,
            artwork: artwork[entry.instanceId]!,
            sortField: field,
            instanceName: showsInstance ? names[entry.instanceId] : null,
            onTap: tap(entry),
            onLongPress: longPress(entry),
            selected: marked(entry),
          );
        },
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final margin = screenMargin(constraints.crossAxisExtent);
        final available = constraints.crossAxisExtent - 2 * margin;
        // Larger text needs wider posters, but two stay side by side: one
        // alone would fill the screen.
        final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
          1.0,
          1.5,
        );
        final columns = math.max(
          2,
          (available + _gridSpacing) ~/ (_posterWidth * scale + _gridSpacing),
        );
        final width = (available - (columns - 1) * _gridSpacing) / columns;
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, 4, margin, margin),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: _gridSpacing * 2,
              crossAxisSpacing: _gridSpacing,
              mainAxisExtent: LibraryGridTile.height(
                context,
                width,
                showsInstance: showsInstance,
              ),
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return LibraryGridTile(
                key: keyOf(entry),
                entry: entry,
                artwork: artwork[entry.instanceId]!,
                width: width,
                instanceName: showsInstance ? names[entry.instanceId] : null,
                onTap: tap(entry),
                onLongPress: longPress(entry),
                selected: marked(entry),
              );
            },
          ),
        );
      },
    );
  }

  /// Opens the item's screen, which its module owns.
  void _open(LibraryState state, LibraryEntry entry) {
    final active = state.source(entry.instanceId)?.active;
    final library = active?.capability(CapabilityKind.library);
    if (library == null) return;
    String location;
    // A module without detail screens yet throws; the page says so.
    try {
      location = library.detailRoute(entry.item.ref).location;
    } on UnimplementedError {
      location = itemPlaceholderLocation(entry.instanceId, entry.item.title);
    }
    unawaited(context.push<void>(location));
  }
}
