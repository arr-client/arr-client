import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'calendar_data.dart';
import 'service_answer.dart';
import 'today.dart';

/// One read from every service that offers [kind], each answering on its own, so
/// that one that fails or is slow does not hold up the others. What a service
/// gave stays while it is read again, also if that fails. It is read again
/// when the app resumes and when the user asks ([calendarRefreshProvider]).
abstract class ServiceReadNotifier<P extends Capability, T>
    extends Notifier<ServiceAnswers<T>?> {
  /// What a service has to offer to be asked.
  CapabilityKind<P> get kind;

  /// Whether a service of that [kind] has what is read.
  bool offers(P provider) => true;

  /// The read this is.
  ServiceResult<List<T>> read(P provider);

  var _answers = <ServiceAnswer<T>>[];

  /// The reads under way, each with what completes when it has ended.
  final _underWay = <StreamSubscription<void>, Completer<void>>{};

  /// The latest read of each instance, so that an older one cannot overtake it.
  final _latest = <String, int>{};
  var _reads = 0;

  @override
  ServiceAnswers<T>? build() {
    // Only which instances there are, and as what: the scope is also replaced
    // when no more than a connection changes.
    ref.watch(scopeProvider.select(_servicesKey));
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(reload()));
    ref.listen(calendarRefreshProvider, (_, _) => unawaited(reload()));
    ref.onDispose(() {
      lifecycle.dispose();
      // A cancelled read never ends by itself, and whoever waits for it, such
      // as the indicator of a pull to refresh, outlasts what is disposed here.
      for (final MapEntry(key: subscription, value: done)
          in _underWay.entries) {
        unawaited(subscription.cancel());
        done.complete();
      }
      _underWay.clear();
      _latest.clear();
    });

    final scope = ref.read(scopeProvider);
    if (scope == null) return null;
    _answers = [
      for (final (active, provider) in scope.providers(kind))
        if (offers(provider))
          ServiceAnswer(
            instanceId: active.instance.id,
            name: active.instance.name,
            loading: true,
          ),
    ];
    unawaited(_load(scope));
    return List.unmodifiable(_answers);
  }

  /// Reads again, from every service or only from [instanceId]. Completes when
  /// they have answered, or when this read is no longer wanted.
  Future<void> reload({String? instanceId}) async {
    final scope = ref.read(scopeProvider);
    if (scope == null) return;
    _answers = [
      for (final answer in _answers)
        instanceId == null || answer.instanceId == instanceId
            ? answer.reading()
            : answer,
    ];
    state = List.unmodifiable(_answers);
    await _load(scope, instanceId: instanceId);
  }

  Future<void> _load(ProfileScope scope, {String? instanceId}) {
    final number = ++_reads;
    for (final answer in _answers) {
      if (instanceId == null || answer.instanceId == instanceId) {
        _latest[answer.instanceId] = number;
      }
    }
    final done = Completer<void>();
    late final StreamSubscription<void> subscription;
    subscription = scope
        .aggregate<P, List<T>>(
          kind,
          read,
          where: (active, provider) =>
              (instanceId == null || active.instance.id == instanceId) &&
              offers(provider),
        )
        .listen(
          (aggregate) => _take(aggregate, number),
          onDone: () {
            _underWay.remove(subscription);
            done.complete();
          },
        );
    _underWay[subscription] = done;
    return done.future;
  }

  void _take(Aggregate<List<T>> aggregate, int number) {
    var changed = false;
    for (final part in aggregate.parts) {
      final id = part.instance.instance.id;
      final result = part.result;
      // An answer is taken once, as every later aggregate repeats it.
      if (result == null || _latest[id] != number) continue;
      _latest.remove(id);
      final index = _answers.indexWhere((answer) => answer.instanceId == id);
      if (index < 0) continue;
      _answers[index] = switch (result) {
        Ok(:final value) => _answers[index].answered(
          value,
          ref.read(clockProvider)(),
        ),
        Err(:final error) => _answers[index].failed(error),
      };
      changed = true;
    }
    if (changed) state = List.unmodifiable(_answers);
  }

  String? _servicesKey(ProfileScope? scope) => scope == null
      ? null
      : jsonEncode([
          scope.profileId,
          for (final active in scope.instances)
            if (active.capabilities.contains(kind))
              [
                active.instance.id,
                active.instance.name,
                // Another one after an edit.
                identityHashCode(active.context.http),
              ],
        ]);
}
