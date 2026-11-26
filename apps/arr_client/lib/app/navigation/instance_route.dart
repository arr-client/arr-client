import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import '../providers.dart';
import '../screens/message_page.dart';

/// A route under `/instances/:instanceId/`. It shows its screen while the
/// instance is one of the active scope, and otherwise says why it cannot: the
/// instance was removed or disabled, or belongs to another profile, to which it
/// offers to switch.
class InstanceRoute extends ConsumerWidget {
  const InstanceRoute({
    required this.instanceId,
    required this.builder,
    this.serviceType,
    super.key,
  });

  final String instanceId;

  /// The module that owns the screen; null for a screen of the app.
  final String? serviceType;

  final Widget Function(BuildContext context, ActiveInstance instance) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final active = ref.watch(scopeProvider)?.instance(instanceId);
    if (active != null) {
      if (serviceType != null && active.instance.serviceType != serviceType) {
        return MessagePage(message: strings.pageUnknown);
      }
      // An edited instance has another client: its screen starts over.
      return KeyedSubtree(
        key: ObjectKey(active.context.http),
        child: builder(context, active),
      );
    }

    final modules = ref.watch(appServicesProvider).modules;
    return switch (ref.watch(savedInstanceProvider(instanceId))) {
      AsyncData(value: null) => MessagePage(message: strings.instanceRemoved),
      AsyncData(value: final saved?) when !saved.isInActiveProfile =>
        MessagePage(
          message: strings.instanceOtherProfile(
            saved.instance.name,
            saved.profile.name,
          ),
          action: _SwitchProfile(saved.profile),
        ),
      AsyncData(value: final saved?) when !saved.instance.enabled =>
        MessagePage(message: strings.instanceDisabled(saved.instance.name)),
      AsyncData(value: final saved?)
          when modules[saved.instance.serviceType] == null =>
        MessagePage(message: strings.instanceUnsupported(saved.instance.name)),
      AsyncError() => MessagePage(message: strings.loadFailed),
      // Not read yet, or the registry has yet to apply what was saved.
      _ => const LoadingPage(),
    };
  }
}

class _SwitchProfile extends ConsumerWidget {
  const _SwitchProfile(this.profile);

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return FilledButton(
      onPressed: () async {
        final services = ref.read(appServicesProvider);
        // Taken now: this button is gone as soon as the switch begins.
        final messenger = ScaffoldMessenger.of(context);
        try {
          await services.registry.switchTo(profile.id);
        } catch (error) {
          services.log.log(
            LogLevel.warning,
            'The profile could not be switched (${error.runtimeType})',
          );
          if (messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text(strings.switchFailed)),
            );
          }
        }
      },
      child: Text(strings.switchProfile(profile.name)),
    );
  }
}
