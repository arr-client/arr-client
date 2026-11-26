import 'package:core/core.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/radarr_localizations.dart';

/// The title of a part of the movie screen.
class SectionHeading extends StatelessWidget {
  /// Creates a [SectionHeading].
  const SectionHeading(this.text, {super.key});

  /// The localized title.
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Semantics(
      container: true,
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// What is known about a movie besides its overview. What the server does not
/// give is left out; the quality profile says when its name could not be read.
class MovieFacts extends StatelessWidget {
  /// Creates [MovieFacts].
  const MovieFacts({
    required this.movie,
    required this.options,
    required this.onRetry,
    super.key,
  });

  /// The movie.
  final Movie movie;

  /// The server's options, which name the quality profile.
  final ViewState<List<ServerOption>> options;

  /// Reads the options again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = RadarrLocalizations.of(context);
    final profile = switch (options) {
      ViewData(:final value) =>
        value
            .where(
              (option) =>
                  option.kind == ServerOptionKind.qualityProfile &&
                  option.id == movie.qualityProfileId,
            )
            .firstOrNull
            ?.label,
      ViewLoading() || ViewError() => null,
    };
    final failure = switch (options) {
      ViewError(:final failure) when movie.qualityProfileId != null => failure,
      _ => null,
    };
    // A release date is a calendar day, which the server writes as midnight
    // UTC. It is passed on as that day of the device's zone, so that it cannot
    // become the day before.
    String? day(DateTime? date) => date == null
        ? null
        : formatDay(context, DateTime(date.year, date.month, date.day));
    final ratings = [
      for (final rating in movie.ratings)
        if (rating.value > 0) _rating(strings, rating),
    ];
    final facts = <(String, String?)>[
      (strings.movieRating, ratings.isEmpty ? null : ratings.join('\n')),
      (
        strings.movieGenres,
        movie.genres.isEmpty
            ? null
            : movie.genres.join(strings.movieListSeparator),
      ),
      (strings.movieStudio, movie.studio),
      (
        strings.movieRuntime,
        switch (movie.runtime) {
          final runtime? => strings.movieMinutes(runtime.inMinutes),
          null => null,
        },
      ),
      (strings.movieCertification, movie.certification),
      (strings.movieInCinemas, day(movie.inCinemas)),
      (strings.movieDigitalRelease, day(movie.digitalRelease)),
      (strings.moviePhysicalRelease, day(movie.physicalRelease)),
      (strings.movieQualityProfile, profile),
      (strings.moviePath, movie.path),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FactList([
          for (final (name, value) in facts)
            if (value != null) (name, value),
        ]),
        if (failure != null) ...[
          Text(
            strings.movieQualityProfile,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(failureMessage(context, failure)),
          TextButton(
            onPressed: onRetry,
            child: Text(strings.movieRetryQualityProfile),
          ),
        ],
      ],
    );
  }
}

/// The files of a movie, with what is in them.
class MovieFiles extends StatelessWidget {
  /// Creates [MovieFiles].
  const MovieFiles({required this.files, super.key});

  /// The files; a movie has one at most.
  final List<MediaFile> files;

  @override
  Widget build(BuildContext context) {
    final strings = RadarrLocalizations.of(context);
    if (files.isEmpty) return Text(strings.movieNoFile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final file in files)
          FactList([
            if (file.quality case final quality?)
              (strings.movieFileQuality, quality.name),
            if (file.size > 0)
              (strings.movieFileSize, formatBytes(context, file.size)),
            if (file.languages.isNotEmpty)
              (
                strings.movieFileLanguages,
                file.languages
                    .map((language) => language.name)
                    .join(strings.movieListSeparator),
              ),
            if (file.video case final video?) (strings.movieFileVideo, video),
            if (file.audio case final audio?) (strings.movieFileAudio, audio),
            (strings.moviePath, file.path),
          ]),
      ],
    );
  }
}

/// The cast and the crew. Nothing where the server provides none.
class MovieCredits extends StatelessWidget {
  /// Creates [MovieCredits].
  const MovieCredits({
    required this.state,
    required this.offline,
    required this.onRetry,
    super.key,
  });

  /// The credits, in the server's order.
  final ViewState<List<Credit>> state;

  /// Whether the screen already says that the server cannot be loaded.
  final bool offline;

  /// Loads again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = RadarrLocalizations.of(context);
    final credits = switch (state) {
      ViewData(:final value) => value,
      _ => const <Credit>[],
    };
    if (state case ViewData(staleness: null) when credits.isEmpty) {
      return const SizedBox.shrink();
    }
    final cast = [
      for (final credit in credits)
        if (credit.type == CreditType.cast) credit,
    ];
    final others = [
      for (final credit in credits)
        if (credit.type != CreditType.cast) credit,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Also the heading of the loading and failure states.
        if (cast.isNotEmpty || others.isEmpty)
          SectionHeading(strings.movieCast),
        _SectionStatus(state: state, offline: offline, onRetry: onRetry),
        if (cast.isNotEmpty)
          _Expandable(
            shown: 10,
            moreLabel: strings.movieShowAllCast(cast.length),
            children: [
              for (final credit in cast)
                _Entry(
                  title: credit.person,
                  subtitle: switch (credit.character) {
                    final character? => strings.movieAsCharacter(character),
                    null => null,
                  },
                ),
            ],
          ),
        if (others.isNotEmpty) ...[
          SectionHeading(strings.movieCrew),
          _Expandable(
            shown: 5,
            moreLabel: strings.movieShowAllCrew(others.length),
            children: [
              for (final credit in others)
                _Entry(title: credit.person, subtitle: credit.role),
            ],
          ),
        ],
      ],
    );
  }
}

/// How many events the screen shows before the rest are asked for.
const _shownEvents = 5;

/// The newest events of a movie, with a way to all of them.
class MovieHistory extends StatelessWidget {
  /// Creates [MovieHistory].
  const MovieHistory({
    required this.state,
    required this.onRetry,
    required this.onShowAll,
    super.key,
  });

  /// The first page of the events, newest first.
  final ViewState<ResultPage<HistoryEvent>> state;

  /// Reads the history again.
  final VoidCallback onRetry;

  /// Opens the whole history.
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final strings = RadarrLocalizations.of(context);
    final failure = switch (state) {
      ViewError(:final failure) => failure,
      ViewData(:final staleness) => staleness?.failure,
      ViewLoading() => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(strings.movieHistory),
        if (state is ViewLoading)
          LinearProgressIndicator(semanticsLabel: strings.movieHistory),
        if (failure != null) ...[
          Text(strings.movieHistoryFailed),
          Text(failureMessage(context, failure)),
          TextButton(
            onPressed: onRetry,
            child: Text(strings.movieRetryHistory),
          ),
        ],
        if (state case ViewData(:final value))
          if (value.items.isEmpty)
            Text(strings.movieNoHistory)
          else ...[
            for (final event in value.items.take(_shownEvents))
              _event(context, strings, event),
            if (value.items.length > _shownEvents || value.hasMore)
              TextButton(
                onPressed: onShowAll,
                child: Text(strings.movieShowAllHistory),
              ),
          ],
      ],
    );
  }

  Widget _event(
    BuildContext context,
    RadarrLocalizations strings,
    HistoryEvent event,
  ) {
    final (label, icon) = _eventLook(strings, event.eventType);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.sourceTitle.isNotEmpty) Text(event.sourceTitle),
          Text(
            strings.movieDateAndTime(
              formatDay(context, event.date),
              formatTime(context, event.date),
            ),
          ),
        ],
      ),
    );
  }
}

/// That a part is loading, or why it could not be.
class _SectionStatus extends StatelessWidget {
  const _SectionStatus({
    required this.state,
    required this.offline,
    required this.onRetry,
  });

  final ViewState<Object> state;
  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ui = UiLocalizations.of(context);
    final failure = switch (state) {
      ViewLoading() => null,
      ViewError(:final failure) => failure,
      ViewData(:final staleness) => staleness?.failure,
    };
    if (state is ViewLoading) {
      return LinearProgressIndicator(semanticsLabel: ui.loading);
    }
    if (failure == null) return const SizedBox.shrink();
    // The notice at the top gives the reason and the retry once for all.
    if (offline) {
      return state is ViewError
          ? Text(RadarrLocalizations.of(context).movieNotSaved)
          : const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(failureMessage(context, failure)),
        TextButton(onPressed: onRetry, child: Text(ui.retry)),
      ],
    );
  }
}

/// The first [shown] of [children], and a button for the rest.
class _Expandable extends StatefulWidget {
  const _Expandable({
    required this.shown,
    required this.moreLabel,
    required this.children,
  });

  final int shown;
  final String moreLabel;
  final List<Widget> children;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable>
    with AutomaticKeepAliveClientMixin {
  var _all = false;

  // The list would otherwise forget the choice once scrolled away.
  @override
  bool get wantKeepAlive => _all;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cut = !_all && widget.children.length > widget.shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...cut ? widget.children.take(widget.shown) : widget.children,
        if (cut)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () {
                setState(() => _all = true);
                updateKeepAlive();
              },
              child: Text(widget.moreLabel),
            ),
          ),
      ],
    );
  }
}

/// A line of a list: a name and what goes with it.
class _Entry extends StatelessWidget {
  const _Entry({required this.title, required this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.bodyLarge),
            if (subtitle case final subtitle?)
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A score and who gave it. The sources are names, so they are not translated.
String _rating(RadarrLocalizations strings, Rating rating) {
  final (name, percent) = switch (rating.source) {
    'imdb' => ('IMDb', false),
    'tmdb' => ('TMDb', false),
    'trakt' => ('Trakt', false),
    'metacritic' => ('Metacritic', false),
    'rottenTomatoes' => ('Rotten Tomatoes', true),
    final other => (other, false),
  };
  // These two score out of a hundred, in whole numbers.
  final whole =
      rating.source == 'metacritic' || rating.source == 'rottenTomatoes';
  final number = NumberFormat.decimalPatternDigits(
    locale: strings.localeName,
    decimalDigits: whole ? 0 : 1,
  ).format(rating.value);
  final value = percent ? strings.moviePercent(number) : number;
  return [
    if (name.isEmpty) value else strings.movieRatingFrom(name, value),
    if (rating.votes case final votes? when votes > 0)
      strings.movieVotes(votes),
  ].join(strings.movieSeparator);
}

(String, IconData) _eventLook(
  RadarrLocalizations strings,
  HistoryEventType type,
) => switch (type) {
  HistoryEventType.grabbed => (
    strings.movieEventGrabbed,
    Icons.cloud_download_outlined,
  ),
  HistoryEventType.imported => (
    strings.movieEventImported,
    Icons.download_done,
  ),
  HistoryEventType.failed => (strings.movieEventFailed, Icons.error_outline),
  HistoryEventType.renamed => (
    strings.movieEventRenamed,
    Icons.drive_file_rename_outline,
  ),
  HistoryEventType.deleted => (strings.movieEventDeleted, Icons.delete_outline),
  HistoryEventType.other => (strings.movieEventOther, Icons.history),
};
