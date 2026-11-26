/// What an interactive release search reads.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'release_grabs.dart';

/// What is searched for, and the client of its instance. An edited instance has
/// another client, so that what was found through the old one is not shown.
typedef ReleaseSearchKey = ({MediaTarget target, Object client});

/// The releases of one target, searched for while its screen is open.
final releaseSearchProvider = NotifierProvider.autoDispose
    .family<ReleaseSearchController, ReleaseSearchState, ReleaseSearchKey>(
      ReleaseSearchController.new,
    );

/// What is known of the releases of one target.
final class ReleaseSearchState {
  const ReleaseSearchState({
    this.releases,
    this.fetchedAt,
    this.failure,
    this.searching = true,
  });

  /// As last found, in the server's order; null if no search has succeeded.
  final List<Release>? releases;

  /// When [releases] was found.
  final DateTime? fetchedAt;

  /// Why the last search failed; null if it succeeded.
  final ServiceFailure? failure;

  /// Whether a search is under way.
  final bool searching;
}

/// Searches when its screen opens and when the user asks, one search at a time.
/// Nothing is saved on the device. Leaving the screen drops the answer.
final class ReleaseSearchController extends Notifier<ReleaseSearchState> {
  ReleaseSearchController(this.key);

  final ReleaseSearchKey key;

  var _running = false;
  var _retrying = false;

  @override
  ReleaseSearchState build() {
    // Not at once: there is no state to change until this returns.
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(search());
    });
    return const ReleaseSearchState();
  }

  /// Asks the indexers, unless a search is already under way. What was found
  /// before stays until it answers.
  Future<void> search() async {
    final active = _active();
    final provider = active?.capability(CapabilityKind.release);
    if (_running || active == null || provider == null) return;
    _running = true;
    final log = ref.read(appServicesProvider).log;
    ref.read(releaseGrabsProvider.notifier).forgetAccepted(active.instance.id);
    state = ReleaseSearchState(
      releases: state.releases,
      fetchedAt: state.fetchedAt,
      failure: state.failure,
    );
    Result<List<Release>, ServiceFailure> result;
    if (active.instance.authFailed) {
      result = const Err(AuthFailed());
    } else {
      try {
        result = await provider.releases(key.target);
      } catch (error) {
        // The type only: the text of an error may quote an address or a secret.
        log.log(
          LogLevel.error,
          'A release search failed (${error.runtimeType})',
        );
        result = const Err(MalformedResponse());
      }
    }
    _running = false;
    if (!ref.mounted || _active() == null) return;
    state = switch (result) {
      Ok(:final value) => ReleaseSearchState(
        releases: List.unmodifiable(value),
        fetchedAt: DateTime.now(),
        searching: false,
      ),
      Err(:final error) => ReleaseSearchState(
        releases: state.releases,
        fetchedAt: state.fetchedAt,
        failure: error,
        searching: false,
      ),
    };
  }

  /// Searches again at the user's request. After a rejected sign-in this also
  /// has the instance try again, which nothing else here does.
  Future<void> retry() async {
    if (_retrying) return;
    _retrying = true;
    final services = ref.read(appServicesProvider);
    try {
      final active = _active();
      if (active != null &&
          (active.instance.authFailed || state.failure is AuthFailed)) {
        await services.profiles.retryAuth(key.target.item.instanceId);
        await services.registry.refresh();
      }
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'A sign-in could not be retried (${error.runtimeType})',
      );
    } finally {
      _retrying = false;
    }
    if (ref.mounted) await search();
  }

  /// The instance, while it is still the one this was made for.
  ActiveInstance? _active() {
    final active = ref
        .read(appServicesProvider)
        .registry
        .scope
        ?.instance(key.target.item.instanceId);
    return active != null && identical(active.context.http, key.client)
        ? active
        : null;
  }
}
