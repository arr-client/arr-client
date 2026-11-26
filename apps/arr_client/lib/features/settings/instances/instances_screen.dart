/// The services of the active profile (spec story 1): add, edit, rename,
/// reorder, disable and remove.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/navigation/locations.dart';
import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import 'change_instance.dart';
import 'rename_instance_dialog.dart';
import 'status.dart';

/// Lists every instance of the active profile, disabled ones included.
class InstancesScreen extends ConsumerWidget {
  const InstancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final saved = ref.watch(profileInstancesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.moreServices)),
      floatingActionButton: FloatingActionButton.extended(
        // The shell keeps other pages alive, whose buttons would share a tag.
        heroTag: null,
        onPressed: () => context.push(addInstanceLocation),
        icon: const Icon(Icons.add),
        label: Text(strings.addService),
      ),
      body: switch (saved) {
        AsyncData(value: final active?) when active.instances.isNotEmpty =>
          _InstanceList(
            // Another profile's list starts over.
            key: ValueKey(active.profile.id),
            profile: active.profile,
            instances: active.instances,
          ),
        AsyncData() => StateMessage(
          icon: Icons.dns_outlined,
          message: strings.noServicesInProfile,
        ),
        AsyncError() => StateMessage(
          icon: Icons.error_outline,
          message: strings.loadFailed,
          announce: true,
        ),
        _ => Center(
          child: CircularProgressIndicator(
            semanticsLabel: UiLocalizations.of(context).loading,
          ),
        ),
      },
    );
  }
}

enum _Action { edit, rename, enable, disable, moveUp, moveDown, remove }

class _InstanceList extends ConsumerStatefulWidget {
  const _InstanceList({
    required this.profile,
    required this.instances,
    super.key,
  });

  final Profile profile;
  final List<Instance> instances;

  @override
  ConsumerState<_InstanceList> createState() => _InstanceListState();
}

class _InstanceListState extends ConsumerState<_InstanceList> {
  /// The order a move asks for, shown until what is saved has been read again.
  List<Instance>? _moved;

  @override
  void didUpdateWidget(_InstanceList old) {
    super.didUpdateWidget(old);
    if (!identical(old.instances, widget.instances)) _moved = null;
  }

  List<Instance> get _shown => _moved ?? widget.instances;

  @override
  Widget build(BuildContext context) {
    final instances = _shown;
    final modules = ref.watch(appServicesProvider).modules;
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      // So that the last row can be scrolled above the add button.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: instances.length,
      onReorderItem: _move,
      itemBuilder: (context, index) => _tile(
        context,
        index,
        instances,
        modules[instances[index].serviceType],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    int index,
    List<Instance> instances,
    ServiceModule? module,
  ) {
    final strings = AppLocalizations.of(context);
    final instance = instances[index];
    final row = ListTile(
      leading: Icon(module?.descriptor.icon ?? Icons.help_outline),
      title: Text(instance.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(module?.descriptor.displayName ?? strings.serviceUnsupported),
          // Holds no secret: an address has no user information or query.
          Text('${instance.url}'),
          if (!instance.enabled) Text(strings.serviceDisabled),
        ],
      ),
      onTap: module == null ? null : () => _edit(instance),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<_Action>(
            tooltip: strings.serviceOptions(instance.name),
            onSelected: (action) => _act(action, instance),
            itemBuilder: (context) => [
              // What this version cannot read it can only move and remove.
              if (module != null) ...[
                PopupMenuItem(
                  value: _Action.edit,
                  child: Text(strings.serviceEdit),
                ),
                PopupMenuItem(
                  value: _Action.rename,
                  child: Text(strings.serviceRename),
                ),
                PopupMenuItem(
                  value: instance.enabled ? _Action.disable : _Action.enable,
                  child: Text(
                    instance.enabled
                        ? strings.serviceDisable
                        : strings.serviceEnable,
                  ),
                ),
              ],
              // For those who cannot drag.
              if (index > 0)
                PopupMenuItem(
                  value: _Action.moveUp,
                  child: Text(strings.serviceMoveUp),
                ),
              if (index < instances.length - 1)
                PopupMenuItem(
                  value: _Action.moveDown,
                  child: Text(strings.serviceMoveDown),
                ),
              PopupMenuItem(
                value: _Action.remove,
                child: Text(strings.serviceRemove),
              ),
            ],
          ),
          if (instances.length > 1)
            // Screen readers have the list's own move actions instead.
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox.square(
                dimension: 48,
                child: Icon(Icons.drag_handle),
              ),
            ),
        ],
      ),
    );
    return Column(
      key: ValueKey(instance.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        // A disabled one has no traffic and nothing to say.
        if (instance.enabled && module != null)
          Padding(
            // Under the name, not the icon.
            padding: const EdgeInsetsDirectional.only(
              start: 56,
              end: 16,
              bottom: 8,
            ),
            child: InstanceStatus(instance: instance, module: module),
          ),
      ],
    );
  }

  void _edit(Instance instance) =>
      unawaited(context.push(editInstanceLocation(instance.id)));

  void _act(_Action action, Instance instance) {
    // Where it is now: the order can change while the menu is open.
    final index = _shown.indexWhere((shown) => shown.id == instance.id);
    if (index < 0) return;
    switch (action) {
      case _Action.edit:
        _edit(instance);
      case _Action.rename:
        unawaited(showRenameInstanceDialog(context, ref, instance));
      case _Action.enable:
        unawaited(_setEnabled(instance, true));
      case _Action.disable:
        unawaited(_setEnabled(instance, false));
      case _Action.moveUp:
        unawaited(_move(index, index - 1));
      case _Action.moveDown:
        unawaited(_move(index, index + 1));
      case _Action.remove:
        unawaited(_remove(instance));
    }
  }

  /// Moves the instance at [from] to be at [to].
  Future<void> _move(int from, int to) async {
    // A move offered at one end of the list may no longer fit.
    if (from == to || to < 0 || to >= _shown.length) return;
    final order = [..._shown];
    final instance = order.removeAt(from);
    order.insert(to, instance);
    setState(() => _moved = order);
    final profiles = ref.read(appServicesProvider).profiles;
    final saved = await _save(
      () => profiles.reorderInstances(widget.profile.id, [
        for (final instance in order) instance.id,
      ]),
    );
    if (!saved && mounted) setState(() => _moved = null);
  }

  Future<void> _setEnabled(Instance instance, bool enabled) async {
    final profiles = ref.read(appServicesProvider).profiles;
    await _save(() async {
      final refused = await changeInstance(
        profiles,
        instance.id,
        enabled: enabled,
      );
      if (refused != null) throw StateError('Refused: ${refused.name}');
    });
  }

  Future<void> _remove(Instance instance) async {
    final strings = AppLocalizations.of(context);
    final profiles = ref.read(appServicesProvider).profiles;
    final confirmed = await showConfirmDialog(
      context,
      title: strings.removeServiceTitle,
      target: instance.name,
      consequence: strings.removeServiceConsequence(widget.profile.name),
      confirmLabel: strings.removeService,
    );
    if (!confirmed || !mounted) return;
    // Erases the secrets and the cache. The instance registry, which follows
    // what is saved, clears the artwork.
    await _save(() => profiles.deleteInstance(instance.id));
  }

  /// Runs [change], and says so if it fails. False if it did.
  Future<bool> _save(Future<void> Function() change) async {
    // Taken now: the list may be gone by the time the change fails.
    final log = ref.read(appServicesProvider).log;
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).changeFailed;
    try {
      await change();
      return true;
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      log.log(
        LogLevel.warning,
        'A service could not be changed (${error.runtimeType})',
      );
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failed)));
      }
      return false;
    }
  }
}
