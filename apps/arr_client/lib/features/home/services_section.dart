import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation/destinations.dart';
import '../../app/navigation/locations.dart';
import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../settings/instances/status.dart';
import 'home_section.dart';

/// The status of each enabled instance of the active profile. A disabled one
/// contributes nothing to Home (spec story 1, scenario 7).
class ServicesSection extends ConsumerWidget {
  const ServicesSection({required this.instances, super.key});

  /// All of the active profile, in their order.
  final List<Instance> instances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final modules = ref.watch(appServicesProvider).modules;
    final enabled = [
      for (final instance in instances)
        if (instance.enabled) instance,
    ];
    return HomeSection(
      title: strings.moreServices,
      children: [
        if (enabled.isEmpty) ListTile(title: Text(strings.allServicesDisabled)),
        for (final instance in enabled)
          _tile(context, instance, modules[instance.serviceType]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextButton(
              onPressed: () => context.go(moreLocation(MoreEntry.services)),
              child: Text(strings.manageServices),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    Instance instance,
    ServiceModule? module,
  ) => ListTile(
    // What a row is doing stays with its instance when the order changes.
    key: ValueKey(instance.id),
    leading: Icon(module?.descriptor.icon ?? Icons.help_outline),
    title: Text(instance.name),
    subtitle: module == null
        ? Text(AppLocalizations.of(context).serviceUnsupported)
        : InstanceStatus(instance: instance, module: module),
    // The form, which a status may ask the user to correct.
    onTap: module == null
        ? null
        : () => unawaited(context.push(editInstanceLocation(instance.id))),
  );
}
