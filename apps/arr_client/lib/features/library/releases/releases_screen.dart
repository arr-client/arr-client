import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'grab_release.dart';
import 'release_filter_sheet.dart';
import 'release_grabs.dart';
import 'release_search_controller.dart';
import 'release_tile.dart';
import 'release_toolbar.dart';
import 'release_view.dart';

/// Interactive search: the releases the indexers have for [target], to sort,
/// filter and grab.
class ReleasesScreen extends ConsumerStatefulWidget {
  const ReleasesScreen({
    required this.instance,
    required this.target,
    super.key,
  });

  /// The instance that holds the target.
  final ActiveInstance instance;

  final MediaTarget target;

  @override
  ConsumerState<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends ConsumerState<ReleasesScreen> {
  /// Kept while the screen is open, over searches.
  final _view = ValueNotifier(const ReleaseView());
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _view.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _view.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (widget.instance.capability(CapabilityKind.release) == null) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.releases)),
        body: SafeArea(
          child: StateMessage(
            icon: Icons.info_outline,
            message: strings.notOffered,
          ),
        ),
      );
    }

    final provider = releaseSearchProvider((
      target: widget.target,
      client: widget.instance.context.http,
    ));
    final search = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    void retry() => unawaited(controller.retry());
    final releases = search.releases;
    final fetchedAt = search.fetchedAt;
    final failure = search.failure;

    final Widget body;
    if (releases == null && (search.searching || failure == null)) {
      body = const _Searching();
    } else {
      final ViewState<List<Release>> view;
      if (releases != null && fetchedAt != null) {
        view = ViewData(
          releases,
          // Nothing is grabbed from results that are being replaced.
          staleness: search.searching || failure != null
              ? Staleness(
                  fetchedAt: fetchedAt,
                  failure: search.searching ? null : failure,
                )
              : null,
        );
      } else {
        view = ViewError(failure ?? const MalformedResponse());
      }
      body = StateScaffold<List<Release>>(
        state: view,
        itemId: widget.target,
        onRetry: retry,
        isEmpty: (releases) => releases.isEmpty,
        emptyMessage: strings.releasesNone,
        builder: (context, releases, {required isStale}) =>
            _results(releases, canGrab: !isStale),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.releases),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.releasesSearchAgain,
            onPressed: search.searching ? null : retry,
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _results(List<Release> releases, {required bool canGrab}) {
    final strings = AppLocalizations.of(context);
    final view = _view.value;
    final shown = view.apply(releases);
    final marks = ref.watch(releaseGrabsProvider);
    final id = widget.instance.instance.id;

    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = EdgeInsets.symmetric(
          horizontal: screenMargin(constraints.maxWidth),
        );
        return CustomScrollView(
          slivers: [
            // Scrolls away, which leaves room at large text sizes.
            SliverPadding(
              padding: margin.copyWith(top: 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReleaseToolbar(
                      view: view,
                      text: _text,
                      onChanged: (changed) => _view.value = changed,
                      onFilters: () => unawaited(
                        showReleaseFilters(
                          this.context,
                          releases: releases,
                          view: _view,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(strings.releasesCount(shown.length, releases.length)),
                  ],
                ),
              ),
            ),
            if (shown.isEmpty)
              SliverPadding(
                padding: margin.copyWith(top: 24, bottom: 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Text(
                        strings.releasesNoneMatch,
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () {
                          _text.clear();
                          _view.value = view.withoutFilters();
                        },
                        child: Text(strings.libraryClearFilters),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: margin.copyWith(bottom: 8),
                sliver: SliverList.separated(
                  itemCount: shown.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final release = shown[index];
                    return ReleaseTile(
                      key: ObjectKey(release),
                      release: release,
                      mark: marks[grabKey(id, release)],
                      onGrab: canGrab
                          // The screen's context, which outlives the row.
                          ? () => unawaited(
                              grabRelease(
                                this.context,
                                ref,
                                widget.instance,
                                release,
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The wait for the indexers, which can be long. The screen can be left.
class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(screenMargin(constraints.maxWidth)),
          child: Column(
            children: [
              CircularProgressIndicator(
                semanticsLabel: UiLocalizations.of(context).loading,
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  strings.releasesSearching,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
