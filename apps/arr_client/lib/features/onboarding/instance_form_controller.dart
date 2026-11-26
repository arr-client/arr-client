/// The state of the add and edit form.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/composition.dart';
import '../../app/providers.dart';
import 'connection_tester.dart';

/// What a form is about: a new instance of [serviceType], or the saved
/// instance [instanceId].
typedef FormTarget = ({String? serviceType, String? instanceId});

/// What the form starts from.
sealed class FormSeed {
  const FormSeed();
}

/// A form that can be filled in.
final class FormReady extends FormSeed {
  const FormReady({
    required this.module,
    required this.profileId,
    required this.suggestedName,
    this.instance,
    this.credential,
    this.credentialUnreadable = false,
  });

  final ServiceModule module;

  /// The profile the instance is, or will be, in.
  final String profileId;

  final String suggestedName;

  /// The instance being edited; null when adding.
  final Instance? instance;

  /// The stored credential of [instance].
  final Credential? credential;

  /// The secure storage failed; what is entered replaces what is there.
  final bool credentialUnreadable;
}

/// The instance to edit does not exist.
final class FormInstanceRemoved extends FormSeed {
  const FormInstanceRemoved();
}

/// The app has no module for the service.
final class FormUnsupported extends FormSeed {
  const FormUnsupported(this.name);

  final String name;
}

/// Read once, so that a saved change does not overwrite what is being typed.
final formSeedProvider = FutureProvider.autoDispose
    .family<FormSeed, FormTarget>((ref, target) async {
      final services = ref.watch(appServicesProvider);
      final instanceId = target.instanceId;
      if (instanceId == null) {
        final serviceType = target.serviceType ?? '';
        final module = services.modules[serviceType];
        if (module == null) return FormUnsupported(serviceType);
        final profileId = (await services.preferences.read()).activeProfileId!;
        return FormReady(
          module: module,
          profileId: profileId,
          suggestedName: _freeName(
            module.descriptor.displayName,
            await services.profiles.instances(profileId),
          ),
        );
      }
      final instance = await services.profiles.instance(instanceId);
      if (instance == null) return const FormInstanceRemoved();
      final module = services.modules[instance.serviceType];
      if (module == null) return FormUnsupported(instance.name);
      Credential? credential;
      var unreadable = false;
      try {
        credential = await services.profiles.credential(instanceId);
      } catch (error) {
        unreadable = true;
        services.log.log(
          LogLevel.warning,
          'A stored credential could not be read (${error.runtimeType})',
        );
      }
      return FormReady(
        module: module,
        profileId: instance.profileId,
        suggestedName: instance.name,
        instance: instance,
        credential: credential,
        credentialUnreadable: unreadable,
      );
    });

/// [base], or [base] with the first number that no instance has.
String _freeName(String base, List<Instance> instances) {
  final taken = {for (final other in instances) other.name.toLowerCase()};
  var name = base;
  for (var number = 2; taken.contains(name.toLowerCase()); number++) {
    name = '$base $number';
  }
  return name;
}

/// How the test of what is in the form went.
sealed class TestStatus {
  const TestStatus();
}

/// Not tested, or changed since.
final class NotTested extends TestStatus {
  const NotTested();
}

final class Testing extends TestStatus {
  const Testing();
}

final class TestPassed extends TestStatus {
  const TestPassed(this.probe);

  final ProbeResult probe;
}

final class TestFailed extends TestStatus {
  const TestFailed(this.input, this.failure);

  /// What was tested.
  final ConnectionInput input;
  final ServiceFailure failure;
}

final class InstanceFormState {
  const InstanceFormState({
    this.test = const NotTested(),
    this.isSaving = false,
  });

  final TestStatus test;
  final bool isSaving;
}

final instanceFormProvider = NotifierProvider.autoDispose
    .family<InstanceFormController, InstanceFormState, FormTarget>(
      InstanceFormController.new,
    );

/// Tests and saves what the form holds.
class InstanceFormController extends Notifier<InstanceFormState> {
  InstanceFormController(this.target);

  final FormTarget target;

  ConnectionTest? _running;

  @override
  InstanceFormState build() {
    ref.onDispose(() => _running?.cancel());
    return const InstanceFormState();
  }

  /// Forgets the test, because what it tested has changed.
  void invalidate() {
    _running?.cancel();
    _running = null;
    if (state.test is! NotTested) state = const InstanceFormState();
  }

  Future<void> test(
    FormReady seed,
    ConnectionInput input,
    ExplainLocalNetwork explain,
  ) async {
    if (state.isSaving) return;
    _running?.cancel();
    final services = ref.read(appServicesProvider);
    final run = _running = ConnectionTest(
      module: seed.module,
      input: input,
      log: services.log,
      localNetwork: services.localNetwork,
      artwork: services.artwork,
      cache: services.cache,
      navigator: services.navigator,
    );
    state = const InstanceFormState(test: Testing());
    final answer = await run.run(explain);
    // Changed, replaced or left meanwhile.
    if (!ref.mounted || !identical(_running, run)) return;
    _running = null;
    state = InstanceFormState(
      test: switch (answer) {
        Ok(:final value) => TestPassed(value),
        Err(:final error) => TestFailed(input, error),
      },
    );
    if (answer case Err(error: AuthFailed())) {
      await _latchIfSaved(services, seed, input);
    }
  }

  /// A rejection of exactly what is saved stops automatic attempts with it.
  /// Does nothing if the form differs from what is saved.
  Future<void> _latchIfSaved(
    AppServices services,
    FormReady seed,
    ConnectionInput input,
  ) async {
    final instance = seed.instance;
    if (instance == null) return;
    try {
      await services.profiles.rejectAuth((
        instance: Instance(
          id: instance.id,
          profileId: instance.profileId,
          name: instance.name,
          serviceType: instance.serviceType,
          url: input.url,
          authKind: input.authKind,
          createdAt: instance.createdAt,
          updatedAt: instance.updatedAt,
        ),
        credential: input.credential,
      ));
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'A rejected sign-in could not be recorded (${error.runtimeType})',
      );
    }
  }

  /// Saves [input] under [name]. What the last test found goes with it: a
  /// passed one its probe, a rejected sign-in the latch that keeps the app
  /// from sending it again by itself. The caller must [invalidate] when what
  /// was tested changes.
  ///
  /// Throws what the storage throws.
  Future<Result<Instance, RuleViolation>> save(
    FormReady seed,
    String name,
    ConnectionInput input,
  ) async {
    final services = ref.read(appServicesProvider);
    _running?.cancel();
    _running = null;
    final tested = state.test is Testing ? const NotTested() : state.test;
    state = InstanceFormState(test: tested, isSaving: true);
    try {
      final old = seed.instance;
      final draft = InstanceDraft(
        name: name,
        serviceType: seed.module.id,
        url: input.url,
        authKind: input.authKind,
        // Null keeps the stored one, unless the origin changed.
        acceptedCertPin: input.certPin,
        customCa: input.customCa,
        probe: tested is TestPassed
            ? services.modules.snapshotOf(seed.module.id, tested.probe)
            : null,
        authRejected: tested is TestFailed && tested.failure is AuthFailed,
        enabled: old?.enabled ?? true,
        links: old?.links ?? const [],
      );
      final result = old == null
          ? await services.profiles.addInstance(
              seed.profileId,
              draft,
              credential: input.credential,
            )
          : await services.profiles.updateInstance(
              old.id,
              draft,
              credential: input.credential,
            );
      if (result is Ok) {
        // The user tested what was refused before, and it works now.
        if (old != null && tested is TestPassed) {
          await services.profiles.retryAuth(old.id);
        }
        try {
          await services.registry.refresh();
        } catch (error) {
          services.log.log(
            LogLevel.warning,
            'The profiles could not be read (${error.runtimeType})',
          );
        }
      }
      return result;
    } finally {
      if (ref.mounted) state = InstanceFormState(test: state.test);
    }
  }
}
