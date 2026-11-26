import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

/// One movie of one instance, and what answers for it.
///
/// Equal to another of the same movie and [instance], whatever the providers:
/// those are made from the instance.
final class MovieDetailSource {
  /// Creates a [MovieDetailSource].
  const MovieDetailSource({
    required this.instance,
    required this.movieId,
    required this.library,
    required this.history,
  });

  /// The instance that holds the movie. Everything is read from it.
  final InstanceContext instance;

  /// The server's id of the movie.
  final int movieId;

  /// The instance's library.
  final LibraryProvider library;

  /// The instance's history.
  final HistoryProvider history;

  /// The movie's key.
  ItemRef get item => ItemRef(
    instanceId: instance.instance.id,
    kind: MediaKind.movie,
    remoteId: movieId,
  );

  @override
  bool operator ==(Object other) =>
      other is MovieDetailSource &&
      identical(other.instance, instance) &&
      other.movieId == movieId;

  @override
  int get hashCode => Object.hash(identityHashCode(instance), movieId);
}

/// What the movie screen has to show. Each part loads on its own, so that one
/// that is slow or fails does not hold back the others.
final class MovieDetailState {
  /// Creates a [MovieDetailState].
  const MovieDetailState({
    this.movie = const ViewLoading(),
    this.files = const ViewLoading(),
    this.credits = const ViewLoading(),
    this.history = const ViewLoading(),
    this.options = const ViewLoading(),
  });

  /// The movie itself.
  final ViewState<Movie> movie;

  /// Its files.
  final ViewState<List<MediaFile>> files;

  /// Its cast and crew.
  final ViewState<List<Credit>> credits;

  /// Its history, newest first.
  final ViewState<List<HistoryEvent>> history;

  /// The server's options, for the name of the quality profile.
  final ViewState<List<ServerOption>> options;

  /// This with the given parts replaced.
  MovieDetailState copyWith({
    ViewState<Movie>? movie,
    ViewState<List<MediaFile>>? files,
    ViewState<List<Credit>>? credits,
    ViewState<List<HistoryEvent>>? history,
    ViewState<List<ServerOption>>? options,
  }) => MovieDetailState(
    movie: movie ?? this.movie,
    files: files ?? this.files,
    credits: credits ?? this.credits,
    history: history ?? this.history,
    options: options ?? this.options,
  );
}

/// The state of one movie screen, for as long as it is shown.
final movieDetailProvider = NotifierProvider.autoDispose
    .family<MovieDetailController, MovieDetailState, MovieDetailSource>(
      MovieDetailController.new,
    );

/// Shows the movie as last fetched, then what the server answers.
class MovieDetailController extends Notifier<MovieDetailState> {
  /// Creates the controller of [source].
  MovieDetailController(this.source);

  /// What is shown and where it comes from.
  final MovieDetailSource source;

  // Only the answers of the latest load count.
  var _load = 0;

  // When the movie on screen was fetched.
  DateTime? _fetchedAt;

  @override
  MovieDetailState build() {
    _load = 0;
    _fetchedAt = null;
    // Not during build, which must not set the state.
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(_open());
    });
    return const MovieDetailState();
  }

  Future<void> _open() async {
    final cached = await source.library.cachedItem(source.item);
    if (!ref.mounted) return;
    if (cached case Ok(
      value: Cached(value: final Movie movie, :final fetchedAt),
    )) {
      _fetchedAt = fetchedAt;
      state = state.copyWith(
        movie: ViewData(movie, staleness: Staleness(fetchedAt: fetchedAt)),
      );
    }
    await refresh();
  }

  /// Asks the server for everything again. Completes when all has answered.
  Future<void> refresh() async {
    final load = ++_load;
    bool current() => ref.mounted && load == _load;

    // What failed shows as loading again; what is on screen stays.
    state = MovieDetailState(
      movie: _retrying(state.movie),
      files: _retrying(state.files),
      credits: _retrying(state.credits),
      history: _retrying(state.history),
      options: _retrying(state.options),
    );

    Future<void> part<T>(
      ServiceResult<T> answer,
      ViewState<T> Function() shown,
      MovieDetailState Function(ViewState<T> next) put,
    ) async {
      final result = await answer;
      if (current()) state = put(_after(result, shown()));
    }

    final item = source.item;
    await Future.wait([
      _movie(current),
      part(
        source.library.files(item),
        () => state.files,
        (next) => state.copyWith(files: next),
      ),
      part(
        source.library.credits(item),
        () => state.credits,
        (next) => state.copyWith(credits: next),
      ),
      part(
        _history(),
        () => state.history,
        (next) => state.copyWith(history: next),
      ),
      part(
        source.library.options(),
        () => state.options,
        (next) => state.copyWith(options: next),
      ),
    ]);
  }

  Future<void> _movie(bool Function() current) async {
    final result = switch (await source.library.item(source.item)) {
      Ok(value: final Movie movie) => Ok<Movie, ServiceFailure>(movie),
      Ok() => const Err<Movie, ServiceFailure>(MalformedResponse()),
      Err(:final error) => Err<Movie, ServiceFailure>(error),
    };
    if (!current()) return;
    final next = _after(result, state.movie);
    if (result is Ok) _fetchedAt = DateTime.now().toUtc();
    state = state.copyWith(movie: next);
  }

  /// What to show after [result], over what was [shown]: a failure leaves the
  /// data on screen, marked with why it is no newer.
  ViewState<T> _after<T>(
    Result<T, ServiceFailure> result,
    ViewState<T> shown,
  ) => switch (result) {
    Ok(:final value) => ViewData(value),
    Err(:final error) => switch (shown) {
      ViewData(:final value) => ViewData(
        value,
        staleness: Staleness(
          fetchedAt: _fetchedAt ?? DateTime.now().toUtc(),
          failure: error,
        ),
      ),
      _ => ViewError(error),
    },
  };

  ServiceResult<List<HistoryEvent>> _history() async =>
      switch (await source.history.history(target: MediaTarget(source.item))) {
        Ok(:final value) => Ok(value.items),
        Err(:final error) => Err(error),
      };

  static ViewState<T> _retrying<T>(ViewState<T> state) => switch (state) {
    ViewError() => const ViewLoading(),
    ViewData(:final value, :final staleness?) => ViewData(
      value,
      staleness: Staleness(fetchedAt: staleness.fetchedAt),
    ),
    ViewLoading() || ViewData() => state,
  };
}
