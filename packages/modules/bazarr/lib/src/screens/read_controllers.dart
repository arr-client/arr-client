/// What the title, series and manual search screens read.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'bazarr_source.dart';

/// One movie, series or episode of an instance.
typedef MediaKey = ({BazarrSource source, SubtitleMedia media});

/// Reads one thing, when first watched and on [reload]. What was read stays,
/// with its age, while it is read again and if that fails.
abstract class ReadController<T> extends Notifier<ViewState<T>> {
  DateTime _fetchedAt = DateTime.now();
  var _reads = 0;

  /// Asks the server.
  ServiceResult<T> read();

  @override
  ViewState<T> build() {
    // Not at once: there is no state to change until this returns.
    unawaited(Future.microtask(_fetch));
    return const ViewLoading();
  }

  /// Reads again. Only the newest read is believed.
  Future<void> reload() {
    switch (state) {
      case ViewData(:final value):
        state = ViewData(value, staleness: Staleness(fetchedAt: _fetchedAt));
      case ViewError():
        state = const ViewLoading();
      case ViewLoading():
        break;
    }
    return _fetch();
  }

  Future<void> _fetch() async {
    if (!ref.mounted) return;
    final number = ++_reads;
    final answer = await read();
    if (!ref.mounted || number != _reads) return;
    switch (answer) {
      case Ok(:final value):
        _fetchedAt = DateTime.now();
        state = ViewData(value);
      case Err(:final error):
        state = switch (state) {
          ViewData(:final value) => ViewData(
            value,
            staleness: Staleness(fetchedAt: _fetchedAt, failure: error),
          ),
          ViewLoading() || ViewError() => ViewError(error),
        };
    }
  }
}

/// The subtitle state of a movie or episode.
final titleProvider = NotifierProvider.autoDispose
    .family<TitleController, ViewState<SubtitleTitle>, MediaKey>(
      TitleController.new,
    );

/// Reads the subtitle state of a movie or episode.
final class TitleController extends ReadController<SubtitleTitle> {
  /// For [key].
  TitleController(this.key);

  /// What is read.
  final MediaKey key;

  @override
  ServiceResult<SubtitleTitle> read() =>
      key.source.guard(() => key.source.provider.forMedia(key.media));
}

/// The name of a series, to say whose an episode is; null if it cannot be read.
final seriesNameProvider = FutureProvider.autoDispose.family<String?, MediaKey>(
  _seriesName,
);

Future<String?> _seriesName(Ref ref, MediaKey key) async {
  final answer = await key.source.guard(
    () => key.source.provider.forMedia(key.media),
  );
  return switch (answer) {
    Ok(:final value) => value.title,
    Err() => null,
  };
}

/// The episodes of a series.
final episodesProvider = NotifierProvider.autoDispose
    .family<EpisodesController, ViewState<List<SubtitleTitle>>, MediaKey>(
      EpisodesController.new,
    );

/// Reads the episodes of a series.
final class EpisodesController extends ReadController<List<SubtitleTitle>> {
  /// For the series of [key].
  EpisodesController(this.key);

  /// Whose episodes.
  final MediaKey key;

  @override
  ServiceResult<List<SubtitleTitle>> read() => key.source.guard(
    () => key.source.provider.browseEpisodes(key.media.seriesId ?? 0),
  );
}

/// What the providers offer for a movie or episode. Not saved on the device.
final candidatesProvider = NotifierProvider.autoDispose
    .family<CandidatesController, ViewState<List<SubtitleCandidate>>, MediaKey>(
      CandidatesController.new,
    );

/// Searches the providers.
final class CandidatesController
    extends ReadController<List<SubtitleCandidate>> {
  /// For [key].
  CandidatesController(this.key);

  /// What is searched for.
  final MediaKey key;

  @override
  ServiceResult<List<SubtitleCandidate>> read() =>
      key.source.guard(() => key.source.provider.manualSearch(key.media));

  /// Searches anew. What an earlier search offered goes: it may no longer be
  /// had.
  Future<void> searchAgain() {
    state = const ViewLoading();
    return reload();
  }
}
