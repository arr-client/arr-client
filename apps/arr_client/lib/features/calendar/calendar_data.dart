/// What the calendar reads from the active profile's services. Home can read
/// the same providers.
library;

import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'service_answer.dart';
import 'today.dart';

/// The releases dated from `from` up to, but not including, `to`.
typedef DateRange = ({DateTime from, DateTime to});

/// The releases of every service with a calendar; null while switching profile.
final calendarEventsProvider = NotifierProvider.autoDispose
    .family<
      CalendarReadNotifier<CalendarEvent>,
      ServiceAnswers<CalendarEvent>?,
      DateRange
    >(_EventsNotifier.new);

/// How many days, the first included, the agenda lists.
final agendaDaysProvider = NotifierProvider.autoDispose<AgendaDays, int>(
  AgendaDays.new,
);

/// The releases of the agenda's days from the given one on. Asking for more
/// days reads again with what is on screen kept.
final agendaEventsProvider = NotifierProvider.autoDispose
    .family<
      CalendarReadNotifier<CalendarEvent>,
      ServiceAnswers<CalendarEvent>?,
      DateTime
    >(_AgendaNotifier.new);

/// What every service with a calendar imported on one local day, given as its
/// local midnight; null while switching profile.
final importedOnProvider = NotifierProvider.autoDispose
    .family<
      CalendarReadNotifier<ImportedItem>,
      ServiceAnswers<ImportedItem>?,
      DateTime
    >(_ImportsNotifier.new);

/// Counts the refreshes the user has asked for.
final calendarRefreshProvider = NotifierProvider<CalendarRefresh, int>(
  CalendarRefresh.new,
);

class CalendarRefresh extends Notifier<int> {
  @override
  int build() => 0;

  /// Has everything on screen read again.
  void request() => state++;
}

class AgendaDays extends Notifier<int> {
  static const _step = 30;

  @override
  int build() => _step;

  /// Lists later days too.
  void extend() => state += _step;
}

class _AgendaNotifier extends CalendarReadNotifier<CalendarEvent> {
  _AgendaNotifier(this.from);

  final DateTime from;

  @override
  ServiceAnswers<CalendarEvent>? build() {
    ref.listen(agendaDaysProvider, (_, _) => unawaited(reload()));
    return super.build();
  }

  @override
  ServiceResult<List<CalendarEvent>> read(CalendarProvider provider) =>
      provider.events(from, addDays(from, ref.read(agendaDaysProvider)));
}

class _EventsNotifier extends CalendarReadNotifier<CalendarEvent> {
  _EventsNotifier(this.range);

  final DateRange range;

  @override
  ServiceResult<List<CalendarEvent>> read(CalendarProvider provider) =>
      provider.events(range.from, range.to);
}

class _ImportsNotifier extends CalendarReadNotifier<ImportedItem> {
  _ImportsNotifier(this.day);

  final DateTime day;

  @override
  ServiceResult<List<ImportedItem>> read(CalendarProvider provider) =>
      provider.importedOn(day);
}

/// One read from every service with a calendar, each answering on its own, so
/// that one that fails or is slow does not hold up the others. What a service
/// gave stays while it is read again, also if that fails. It is read again
/// when the app resumes and when the user asks.
abstract class CalendarReadNotifier<T> extends Notifier<ServiceAnswers<T>?> {
  /// The read this is.
  ServiceResult<List<T>> read(CalendarProvider provider);

  var _answers = <ServiceAnswer<T>>[];
  final _subscriptions = <StreamSubscription<void>>{};

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
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
      _latest.clear();
    });

    final scope = ref.read(scopeProvider);
    if (scope == null) return null;
    _answers = [
      for (final (active, _) in scope.providers(CapabilityKind.calendar))
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
  /// they have answered.
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
        .aggregate<CalendarProvider, List<T>>(
          CapabilityKind.calendar,
          read,
          where: instanceId == null
              ? null
              : (active, _) => active.instance.id == instanceId,
        )
        .listen(
          (aggregate) => _take(aggregate, number),
          onDone: () {
            _subscriptions.remove(subscription);
            done.complete();
          },
        );
    _subscriptions.add(subscription);
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

  static String? _servicesKey(ProfileScope? scope) => scope == null
      ? null
      : jsonEncode([
          scope.profileId,
          for (final active in scope.instances)
            if (active.capabilities.contains(CapabilityKind.calendar))
              [
                active.instance.id,
                active.instance.name,
                // Another one after an edit.
                identityHashCode(active.context.http),
              ],
        ]);
}
