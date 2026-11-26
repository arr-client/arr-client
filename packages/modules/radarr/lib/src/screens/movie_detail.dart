import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/radarr_localizations.dart';
import 'movie_actions.dart';
import 'movie_actions_controller.dart';
import 'movie_detail_controller.dart';
import 'movie_detail_header.dart';
import 'movie_detail_sections.dart';

/// Everything about one movie: spec story 2, scenario 3.
///
/// It must be below a Riverpod `ProviderScope`. The app fills the `subtitles`
/// and `downloadProgress` slots.
class MovieDetailScreen extends ConsumerWidget {
  /// Creates the screen of [source].
  const MovieDetailScreen({required this.source, super.key});

  /// Which movie, and where it comes from.
  final MovieDetailSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = RadarrLocalizations.of(context);
    final provider = movieDetailProvider(source);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    Future<void> refresh() => ref.read(provider.notifier).refresh();

    // Kept while the screen is, so that the tasks and what covers them are.
    ref.listen(movieActionsProvider(source), (_, _) {});

    return RouteCurrentListener(
      onChanged: (current) =>
          ref.read(movieActionsProvider(source).notifier).shown = current,
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (state.movie) {
            ViewData(staleness: Staleness(failure: NotFound())) => '',
            ViewData(:final value) => value.title,
            ViewLoading() || ViewError() => '',
          }),
          actions: [
            // Pulling down does this too, which a screen reader cannot.
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: strings.movieRefresh,
              onPressed: () => unawaited(refresh()),
            ),
            // Not for a movie that is not there.
            if (state.movie case ViewData(:final value, :final staleness)
                when staleness?.failure is! NotFound)
              MovieMenu(
                source: source,
                movie: value,
                isStale: staleness != null,
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: refresh,
            child: StateScaffold<Movie>(
              state: state.movie,
              itemId: source.item,
              onRetry: () => unawaited(refresh()),
              builder: (context, movie, {required isStale}) => _Content(
                movie,
                state,
                source: source,
                controller: controller,
                isStale: isStale,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content(
    this.movie,
    this.state, {
    required this.source,
    required this.controller,
    required this.isStale,
  });

  final Movie movie;
  final MovieDetailState state;
  final MovieDetailSource source;
  final MovieDetailController controller;
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = RadarrLocalizations.of(context);
    // Whether the notice above already says that the server cannot be loaded.
    final offline = switch (state.movie) {
      ViewData(:final staleness?) => staleness.failure != null,
      _ => false,
    };
    final deleting = ref.watch(
      movieActionsProvider(source).select((state) => state.deletingFile),
    );
    // The screen's own context, which outlives the rows of the list.
    final screen = context;
    // Only a file the instance has just listed can be deleted.
    final listed = switch (state.files) {
      ViewData(:final value, staleness: null) => value,
      _ => null,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = screenMargin(constraints.maxWidth);
        Widget inset(Widget child) => Padding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          child: child,
        );
        return ListView(
          // So that a pull to refresh works when it all fits.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            MovieBackdrop(movie: movie, artwork: source.instance.artwork),
            const SizedBox(height: 16),
            inset(
              MovieHeader(
                movie: movie,
                instanceName: source.instance.instance.name,
                artwork: source.instance.artwork,
              ),
            ),
            inset(
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: MovieActions(
                  source: source,
                  movie: movie,
                  isStale: isStale,
                ),
              ),
            ),
            inset(DetailSlot(DetailSlotName.downloadProgress, item: movie.ref)),
            if (movie.overview case final overview?)
              inset(
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    overview,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            inset(SectionHeading(strings.movieDetails)),
            inset(
              MovieFacts(
                movie: movie,
                options: state.options,
                onRetry: () => unawaited(controller.retryOptions()),
              ),
            ),
            inset(SectionHeading(strings.movieFileHeading)),
            inset(
              MovieFiles(
                // The movie's own record names its file, also while the list of
                // files is not there.
                files: listed ?? [?movie.file],
                onDelete: listed == null || isStale || deleting
                    ? null
                    : (file) => unawaited(
                        deleteMovieFile(screen, ref, source, movie, file),
                      ),
              ),
            ),
            inset(DetailSlot(DetailSlotName.subtitles, item: movie.ref)),
            inset(
              MovieCredits(
                state: state.credits,
                offline: offline,
                onRetry: () => unawaited(controller.retryCredits()),
              ),
            ),
            inset(
              MovieHistory(
                state: state.history,
                onRetry: () => unawaited(controller.retryHistory()),
                onShowAll: () =>
                    unawaited(source.instance.navigator.openHistory(movie.ref)),
              ),
            ),
          ],
        );
      },
    );
  }
}
