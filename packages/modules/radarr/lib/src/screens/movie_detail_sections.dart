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
/// give is left out.
class MovieFacts extends StatelessWidget {
  /// Creates [MovieFacts].
  const MovieFacts({
    required this.movie,
    required this.qualityProfile,
    super.key,
  });

  /// The movie.
  final Movie movie;

  /// The name of its quality profile, where known.
  final String? qualityProfile;

  @override
  Widget build(BuildContext context) {
    final strings = RadarrLocalizations.of(context);
    final ratings = [
      for (final rating in movie.ratings)
        if (rating.value > 0) _rating(strings, rating),
    ];
    // A release date is a calendar day, which the server writes as midnight
    // UTC: moved to the device's zone it could become the day before.
    String? day(DateTime? date) => date == null
        ? null
        : MaterialLocalizations.of(context)
              .formatShortDate(DateTime(date.year, date.month, date.day));
    final facts = <(String, String?)>[
      (
        strings.movieGenres,
        movie.genres.isEmpty ? null : movie.genres.join(', '),
      ),
      (strings.movieStudio, movie.studio),
      (strings.movieRatings, ratings.isEmpty ? null : ratings.join('\n')),
      (strings.movieInCinemas, day(movie.inCinemas)),
      (strings.movieDigitalRelease, day(movie.digitalRelease)),
      (strings.moviePhysicalRelease, day(movie.physicalRelease)),
      (strings.movieQualityProfile, qualityProfile),
      (strings.moviePath, movie.path),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        for (final (label, value) in facts)
          if (value != null) _Fact(label, value),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final file in files) ...[
          if (file.quality case final quality?)
            _Fact(strings.movieFileQuality, quality.name),
          _Fact(strings.movieFileSize, formatBytes(context, file.size)),
          if (file.languages.isNotEmpty)
            _Fact(
              strings.movieFileLanguages,
              file.languages.map((language) => language.name).join(', '),
            ),
          if (file.video case final video?)
            _Fact(strings.movieFileVideo, video),
          if (file.audio case final audio?)
            _Fact(strings.movieFileAudio, audio),
          _Fact(strings.moviePath, file.path),
        ],
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

/// What has happened to a movie.
class MovieHistory extends StatelessWidget {
  /// Creates [MovieHistory].
  const MovieHistory({
    required this.state,
    required this.offline,
    required this.onRetry,
    super.key,
  });

  /// The events, newest first.
  final ViewState<List<HistoryEvent>> state;

  /// Whether the screen already says that the server cannot be loaded.
  final bool offline;

  /// Loads again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = RadarrLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    String when(DateTime date) {
      final local = date.toLocal();
      return strings.movieDateAndTime(
        material.formatShortDate(local),
        material.formatTimeOfDay(
          TimeOfDay.fromDateTime(local),
          alwaysUse24HourFormat: use24,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(strings.movieHistory),
        _SectionStatus(state: state, offline: offline, onRetry: onRetry),
        if (state case ViewData(:final value))
          if (value.isEmpty)
            Text(strings.movieNoHistory)
          else
            _Expandable(
              shown: 5,
              moreLabel: strings.movieShowAllHistory(value.length),
              children: [
                for (final event in value)
                  _Entry(
                    title: _eventLabel(strings, event.eventType),
                    subtitle: '${when(event.date)}\n${event.sourceTitle}',
                  ),
              ],
            ),
      ],
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

/// A label above its value, read as one.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(value, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
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

/// A score on its source's own scale. The sources are names, so they are not
/// translated.
String _rating(RadarrLocalizations strings, Rating rating) {
  final (name, decimals) = switch (rating.source) {
    'imdb' => ('IMDb', 1),
    'tmdb' => ('TMDb', 1),
    'trakt' => ('Trakt', 1),
    'metacritic' => ('Metacritic', 0),
    'rottenTomatoes' => ('Rotten Tomatoes', 0),
    final other => (other, 1),
  };
  final number = NumberFormat.decimalPatternDigits(
    locale: strings.localeName,
    decimalDigits: decimals,
  ).format(rating.value);
  final score = switch (rating.source) {
    'imdb' || 'tmdb' || 'trakt' => strings.movieScoreOutOfTen(number),
    'metacritic' => strings.movieScoreOutOfHundred(number),
    'rottenTomatoes' => strings.movieScorePercent(number),
    _ => number,
  };
  return switch (rating.votes) {
    final votes? when votes > 0 => strings.movieRatingWithVotes(
      votes,
      name,
      score,
    ),
    _ => strings.movieRating(name, score),
  };
}

String _eventLabel(RadarrLocalizations strings, HistoryEventType type) =>
    switch (type) {
      HistoryEventType.grabbed => strings.movieEventGrabbed,
      HistoryEventType.imported => strings.movieEventImported,
      HistoryEventType.failed => strings.movieEventFailed,
      HistoryEventType.renamed => strings.movieEventRenamed,
      HistoryEventType.deleted => strings.movieEventDeleted,
      HistoryEventType.other => strings.movieEventOther,
    };
