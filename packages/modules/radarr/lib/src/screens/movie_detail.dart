import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/radarr_localizations.dart';
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
    Future<void> refresh() => ref.read(provider.notifier).refresh();

    return Scaffold(
      // The movie's title is in the body, where it is never cut short.
      appBar: AppBar(title: Text(strings.movieDetailTitle)),
      body: SafeArea(
        top: false,
        child: StateScaffold<Movie>(
          state: state.movie,
          itemId: source.item,
          onRetry: refresh,
          builder: (context, movie, {required isStale}) => RefreshIndicator(
            onRefresh: refresh,
            child: _Content(movie, state, source: source, onRetry: refresh),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content(
    this.movie,
    this.state, {
    required this.source,
    required this.onRetry,
  });

  final Movie movie;
  final MovieDetailState state;
  final MovieDetailSource source;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = RadarrLocalizations.of(context);
    // Whether the notice above already says that the server cannot be loaded.
    final offline = switch (state.movie) {
      ViewData(:final staleness?) => staleness.failure != null,
      _ => false,
    };
    final profile = switch (state.options) {
      ViewData(:final value) =>
        value
            .where(
              (option) =>
                  option.kind == ServerOptionKind.qualityProfile &&
                  option.id == movie.qualityProfileId,
            )
            .firstOrNull
            ?.label,
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
            inset(MovieFacts(movie: movie, qualityProfile: profile)),
            inset(SectionHeading(strings.movieFileHeading)),
            inset(
              MovieFiles(
                // The movie's own record names its file, also while the list of
                // files is not there.
                files: switch (state.files) {
                  ViewData(:final value, staleness: null) => value,
                  _ => [?movie.file],
                },
              ),
            ),
            inset(DetailSlot(DetailSlotName.subtitles, item: movie.ref)),
            inset(
              MovieCredits(
                state: state.credits,
                offline: offline,
                onRetry: onRetry,
              ),
            ),
            inset(
              MovieHistory(
                state: state.history,
                offline: offline,
                onRetry: onRetry,
              ),
            ),
          ],
        );
      },
    );
  }
}
