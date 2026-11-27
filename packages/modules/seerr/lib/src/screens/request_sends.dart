/// The requests sent while the app runs. A request can have something
/// downloaded, so one is never sent twice by itself, also when its screen is
/// left and opened again.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quota_controller.dart';
import 'seasons_controller.dart';
import 'seerr_source.dart';
import 'title_news.dart';

/// One variant of one title of one instance.
typedef SendKey = ({String instanceId, DiscoveryRef title, bool is4k});

/// What is known of a request sent.
enum SendMark {
  /// It is on its way.
  sending,

  /// It may or may not have arrived.
  unknown,
}

/// The marks of the variants that have one. It outlives the screens.
final requestSendsProvider =
    NotifierProvider<RequestSends, Map<SendKey, SendMark>>(RequestSends.new);

/// Sends requests, each once.
final class RequestSends extends Notifier<Map<SendKey, SendMark>> {
  @override
  Map<SendKey, SendMark> build() => const {};

  /// Asks for [title]. Null, with nothing sent, while a request for the same
  /// variant is on its way; found before anything is awaited, so that a second
  /// call cannot overtake the first.
  Future<Result<MediaRequest, ServiceFailure>>? send(
    SeerrSource source,
    DiscoveryTitle title, {
    required bool is4k,
    List<int> seasons = const [],
  }) {
    final wanted = DiscoveryRef(
      mediaType: title.mediaType,
      tmdbId: title.tmdbId,
    );
    final key = (instanceId: source.instanceId, title: wanted, is4k: is4k);
    final before = state[key];
    if (before == SendMark.sending) return null;
    _mark(key, SendMark.sending);
    return _send(source, title, key, seasons, before);
  }

  Future<Result<MediaRequest, ServiceFailure>> _send(
    SeerrSource source,
    DiscoveryTitle title,
    SendKey key,
    List<int> seasons,
    SendMark? before,
  ) async {
    final result = await source.guard(
      () => source.requests.request(title, is4k: key.is4k, seasons: seasons),
      otherwise: const OutcomeUnknown(),
    );
    if (!ref.mounted) return result;
    // Whatever the answer, what the screens show may be out of date.
    ref.read(titleChangesProvider((source, key.title)).notifier).changed();
    ref
      ..invalidate(seasonsProvider)
      ..invalidate(quotaProvider(source));
    _mark(key, switch (result) {
      Ok() => null,
      Err(error: OutcomeUnknown()) => SendMark.unknown,
      // A refusal says nothing about an earlier request.
      Err() => before,
    });
    return result;
  }

  void _mark(SendKey key, SendMark? mark) {
    final marks = {...state};
    if (mark == null) {
      marks.remove(key);
    } else {
      marks[key] = mark;
    }
    state = marks;
  }
}
