/// The changes asked of a server while the app runs. They outlive the screens,
/// so that one under way is not sent again by leaving a screen and coming back.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bazarr_source.dart';

/// A movie or episode of an instance, by the instance's id, so that it is kept
/// over a reconnection.
typedef RequestKey = ({String instanceId, SubtitleMedia media});

/// What is known of the change last asked for a movie or episode.
enum RequestState {
  /// The server has not answered yet.
  sending,

  /// The server took the request. It may not have done the work yet.
  sent,

  /// No answer: the server may still be at it.
  unknown,
}

/// The state of the changes of each movie and episode that has one.
final requestsProvider =
    NotifierProvider<RequestsController, Map<RequestKey, RequestState>>(
      RequestsController.new,
    );

/// Sends changes, one at a time for each movie or episode.
final class RequestsController extends Notifier<Map<RequestKey, RequestState>> {
  @override
  Map<RequestKey, RequestState> build() => const {};

  /// Sends [write] for [media], once. Null, with nothing sent, while another
  /// change of it is under way; found before anything is awaited, so that a
  /// second call cannot overtake the first.
  ///
  /// [queued] is whether the server may answer before doing what [write] asks.
  Future<Result<void, ServiceFailure>>? send(
    BazarrSource source,
    SubtitleMedia media,
    ServiceResult<void> Function() write, {
    required bool queued,
  }) {
    final key = (instanceId: source.instanceId, media: media);
    if (state[key] == RequestState.sending) return null;
    _mark(key, RequestState.sending);
    return _send(source, key, write, queued);
  }

  Future<Result<void, ServiceFailure>> _send(
    BazarrSource source,
    RequestKey key,
    ServiceResult<void> Function() write,
    bool queued,
  ) async {
    final result = await source.guard(write, otherwise: const OutcomeUnknown());
    if (ref.mounted) {
      _mark(key, switch (result) {
        Ok() when queued => RequestState.sent,
        Err(error: OutcomeUnknown()) => RequestState.unknown,
        Ok() || Err() => null,
      });
    }
    return result;
  }

  /// Drops what is known of an answered request, as the user asks to see how
  /// things stand now.
  void forget(BazarrSource source, SubtitleMedia media) {
    final key = (instanceId: source.instanceId, media: media);
    if (state[key] case RequestState.sent || RequestState.unknown) {
      _mark(key, null);
    }
  }

  void _mark(RequestKey key, RequestState? mark) {
    final marks = {...state};
    if (mark == null) {
      marks.remove(key);
    } else {
      marks[key] = mark;
    }
    state = marks;
  }
}
