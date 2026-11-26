import 'dart:async';

import '../logging/log_level.dart';
import '../logging/logger.dart';
import '../module/capability.dart';
import '../module/capability_kind.dart';
import '../module/result.dart';
import '../module/service_failure.dart';
import '../module/service_result.dart';
import 'active_instance.dart';
import 'aggregate.dart';

/// The active profile's enabled instances at one time. All content, searches
/// and actions come from here. The `InstanceRegistry` makes a new one when
/// anything about them changes.
final class ProfileScope {
  /// Made by the registry. [isCurrent] answers [ProfileScope.isCurrent].
  ProfileScope({
    required this.profileId,
    required this.instances,
    required this._isCurrent,
    required this._log,
  });

  /// The active profile.
  final String profileId;

  /// In the user's order.
  final List<ActiveInstance> instances;

  final bool Function() _isCurrent;
  final Logger _log;

  /// False once another profile is active.
  bool get isCurrent => _isCurrent();

  /// The instance with [id], or null if it is not among [instances].
  ActiveInstance? instance(String id) =>
      instances.where((active) => active.instance.id == id).firstOrNull;

  /// What any of the instances offers; this decides what the app shows.
  Set<CapabilityKind> get capabilities => {
    for (final active in instances) ...active.capabilities,
  };

  /// The instances that offer [kind], each with its implementation.
  List<(ActiveInstance, T)> providers<T extends Capability>(
    CapabilityKind<T> kind,
  ) => [
    for (final active in instances)
      if (active.capability(kind) case final provider?) (active, provider),
  ];

  /// Asks every instance that offers [kind], and that [where] accepts, at the
  /// same time, so that one that fails or is slow does not hold up the others.
  ///
  /// The stream gives an [Aggregate] with all parts pending, then one as each
  /// answer arrives, and closes after the last. A capability or [read] that
  /// throws is that instance's [MalformedResponse]. An instance that stops
  /// being current is left out, and once the profile does, nothing more is
  /// given.
  Stream<Aggregate<R>> aggregate<T extends Capability, R>(
    CapabilityKind<T> kind,
    ServiceResult<R> Function(T provider) read, {
    bool Function(ActiveInstance instance, T provider)? where,
  }) {
    final parts = <InstanceResult<R>>[];
    final asked = <(int, T)>[];
    for (final active in instances) {
      try {
        final provider = active.capability(kind);
        if (provider == null || !(where?.call(active, provider) ?? true)) {
          continue;
        }
        asked.add((parts.length, provider));
        parts.add(InstanceResult(active));
      } catch (error, stackTrace) {
        _report(error, stackTrace);
        parts.add(InstanceResult(active, const Err(MalformedResponse())));
      }
    }

    final controller = StreamController<Aggregate<R>>();
    var pending = asked.length;
    void emit() => controller.add(
      Aggregate([
        for (final part in parts)
          if (part.instance.isCurrent) part,
      ]),
    );

    Future<void> ask(int index, T provider) async {
      Result<R, ServiceFailure> result;
      try {
        result = await read(provider);
      } catch (error, stackTrace) {
        _report(error, stackTrace);
        result = const Err(MalformedResponse());
      }
      parts[index] = InstanceResult(parts[index].instance, result);
      // Dropped by the controller if the listener has cancelled.
      emit();
      if (--pending == 0) unawaited(controller.close());
    }

    controller.onListen = () {
      emit();
      if (pending == 0) unawaited(controller.close());
      for (final (index, provider) in asked) {
        unawaited(ask(index, provider));
      }
    };
    // Checked as each is delivered, which can be after it was added.
    return controller.stream.where((_) => isCurrent);
  }

  // The type only: the text of an error may quote an address or a secret.
  void _report(Object error, StackTrace stackTrace) => _log.log(
    LogLevel.error,
    'A module failed to read (${error.runtimeType})',
    stackTrace: stackTrace,
  );
}
