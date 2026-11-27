/// One title with what the user may do about it.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'seerr_source.dart';
import 'title_news.dart';

/// One title of one instance.
typedef TitleKey = (SeerrSource, DiscoveryRef);

/// A title as last read, and who is looking at it.
final class TitlePage {
  /// Creates a [TitlePage].
  const TitlePage({required this.title, this.user, this.userFailure});

  /// The title, with the status of its requests.
  final DiscoveryTitle title;

  /// What the user may do; null if it could not be read, and then nothing is
  /// offered.
  final SessionUser? user;

  /// Why [user] is null.
  final ServiceFailure? userFailure;
}

/// A title, while a screen shows it.
final titleProvider = NotifierProvider.autoDispose
    .family<TitleController, ViewState<TitlePage>, TitleKey>(
      TitleController.new,
    );

/// Reads a title when first asked for and on refresh. What was read stays, with
/// its age, if a later read fails.
final class TitleController extends Notifier<ViewState<TitlePage>> {
  /// For [key].
  TitleController(this.key);

  /// The title.
  final TitleKey key;

  DateTime _fetchedAt = DateTime.now();
  Future<void>? _loading;

  // Counts the reads, so that only the newest one is believed.
  var _load = 0;

  @override
  ViewState<TitlePage> build() {
    // A request for it, from whichever screen, changes what there is to read.
    ref.listen(titleChangesProvider(key), (_, _) => unawaited(reload()));
    // Not at once: there is no state to change until this returns.
    Future.microtask(refresh);
    return const ViewLoading();
  }

  /// Reads again. A read already under way is not repeated.
  Future<void> refresh() => _loading ?? reload();

  /// Reads again even if a read is under way, whose answer is then dropped: it
  /// may be older than a change just made.
  Future<void> reload() {
    if (!ref.mounted) return Future.value();
    switch (state) {
      case ViewData(:final value):
        state = ViewData(value, staleness: Staleness(fetchedAt: _fetchedAt));
      case ViewError():
        state = const ViewLoading();
      case ViewLoading():
        break;
    }
    final load = ++_load;
    return _loading = _fetch(load).whenComplete(() {
      if (load == _load) _loading = null;
    });
  }

  Future<void> _fetch(int load) async {
    final (source, title) = key;
    final (detail, session) = await (
      source.guard(() => source.discovery.detail(title)),
      source.guard(source.requests.session),
    ).wait;
    if (!ref.mounted || load != _load) return;
    switch (detail) {
      case Ok(:final value):
        _fetchedAt = DateTime.now();
        state = ViewData(
          TitlePage(
            title: value,
            user: switch (session) {
              Ok(:final value) => value,
              Err() => null,
            },
            userFailure: switch (session) {
              Ok() => null,
              Err(:final error) => error,
            },
          ),
        );
        // The list below shows the same title.
        ref.read(readTitleProvider(source).notifier).publish(value);
      case Err(error: NotFound()):
        state = const ViewError(NotFound());
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
