/// What screens read, over the services of the composition root.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'composition.dart';

/// The running app's services; the root widget supplies them.
final appServicesProvider = Provider<AppServices>(
  (ref) => throw StateError('No services'),
);

/// The app-wide preferences.
final preferencesProvider = NotifierProvider<PreferencesNotifier, Preferences>(
  PreferencesNotifier.new,
);

/// The active profile's instances; null while switching.
final scopeProvider = NotifierProvider<ScopeNotifier, ProfileScope?>(
  ScopeNotifier.new,
);

/// The active profile and all its instances, enabled or not, in their order.
typedef ProfileInstances = ({Profile profile, List<Instance> instances});

/// Null without an active profile.
final profileInstancesProvider = StreamProvider.autoDispose<ProfileInstances?>((
  ref,
) {
  final services = ref.watch(appServicesProvider);
  return _onEveryChange(services.profiles, () async {
    final id = (await services.preferences.read()).activeProfileId;
    final profile = (await services.profiles.profiles())
        .where((profile) => profile.id == id)
        .firstOrNull;
    if (profile == null) return null;
    return (
      profile: profile,
      instances: await services.profiles.instances(profile.id),
    );
  });
});

/// A saved instance, its profile and whether that is the active one.
typedef SavedInstance = ({
  Instance instance,
  Profile profile,
  bool isInActiveProfile,
});

/// One instance of any profile; null if there is none with the id.
final savedInstanceProvider = StreamProvider.autoDispose
    .family<SavedInstance?, String>((ref, id) {
      final services = ref.watch(appServicesProvider);
      return _onEveryChange(services.profiles, () async {
        final instance = await services.profiles.instance(id);
        if (instance == null) return null;
        final profile = (await services.profiles.profiles())
            .where((profile) => profile.id == instance.profileId)
            .firstOrNull;
        if (profile == null) return null;
        final active = (await services.preferences.read()).activeProfileId;
        return (
          instance: instance,
          profile: profile,
          isInActiveProfile: active == profile.id,
        );
      });
    });

/// All profiles, in their order, and the id of the active one.
typedef Profiles = ({List<Profile> all, String? activeId});

final profilesProvider = StreamProvider.autoDispose<Profiles>((ref) {
  final services = ref.watch(appServicesProvider);
  return _onEveryChange(services.profiles, () async {
    final activeId = (await services.preferences.read()).activeProfileId;
    return (all: await services.profiles.profiles(), activeId: activeId);
  });
});

/// [read] now and after every change to what [profiles] stores.
Stream<T> _onEveryChange<T>(
  ProfileRepository profiles,
  Future<T> Function() read,
) {
  final triggers = StreamController<void>();
  StreamSubscription<void>? changes;
  triggers
    ..onListen = () {
      changes = profiles.changes.listen(triggers.add);
      triggers.add(null);
    }
    ..onCancel = () async {
      await changes?.cancel();
      unawaited(triggers.close());
    };
  // One read at a time, so that an older one cannot overtake a newer one.
  return triggers.stream.asyncMap((_) => read());
}

/// Follows the stored preferences.
class PreferencesNotifier extends Notifier<Preferences> {
  @override
  Preferences build() {
    final services = ref.watch(appServicesProvider);
    final changes = services.preferences.watch().listen(
      (value) {
        // Whoever rebuilds on this must find what is built on the preferences,
        // such as the artwork loaders, agreeing already.
        services.currentPreferences = value;
        state = value;
      },
      // The composition root logs it.
      onError: (Object _) {},
    );
    ref.onDispose(changes.cancel);
    return services.currentPreferences;
  }
}

/// Follows the instance registry.
class ScopeNotifier extends Notifier<ProfileScope?> {
  @override
  ProfileScope? build() {
    final registry = ref.watch(appServicesProvider).registry;
    final changes = registry.changes.listen((scope) => state = scope);
    ref.onDispose(changes.cancel);
    return registry.scope;
  }
}
