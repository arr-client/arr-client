/// The pages behind `AppNavigator.openEdit` and `openDelete`: a sheet and a
/// dialog over whatever asked for them.
library;

import 'package:core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/navigation/instance_route.dart';
import '../../../app/navigation/locations.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import 'delete_dialog.dart';
import 'edit_sheet.dart';

/// The route of the edit sheet.
GoRoute editItemRoute() => GoRoute(
  path: '/instances/:instanceId/${InstanceFlow.edit.name}',
  pageBuilder: (context, state) => _SheetPage(
    key: state.pageKey,
    child: _item(
      state,
      (instance, library, item) =>
          EditSheet(instance: instance, library: library, item: item),
    ),
  ),
);

/// The route of the delete dialog.
GoRoute deleteItemRoute() => GoRoute(
  path: '/instances/:instanceId/${InstanceFlow.delete.name}',
  pageBuilder: (context, state) => _DialogPage(
    key: state.pageKey,
    child: _item(
      state,
      (instance, library, item) =>
          DeleteDialog(instance: instance, library: library, item: item),
      // An album can be deleted on its own, but has nothing to edit beyond
      // whether it is monitored.
      also: (library, kind) =>
          library.itemKind == MediaKind.artist && kind == MediaKind.album,
    ),
  ),
);

/// What [builder] makes of the item that [state] names, where it names one of
/// those the instance's library holds at its top level, or one that [also]
/// takes. Nothing else can be edited or deleted here.
Widget _item(
  GoRouterState state,
  Widget Function(ActiveInstance, LibraryProvider, ItemRef) builder, {
  bool Function(LibraryProvider library, MediaKind kind)? also,
}) {
  final instanceId = state.pathParameters['instanceId'] ?? '';
  return InstanceRoute(
    instanceId: instanceId,
    builder: (context, active) {
      final item = itemQueryRef(instanceId, state.uri.queryParameters);
      final library = active.capability(CapabilityKind.library);
      if (item != null &&
          library != null &&
          (library.itemKind == item.kind ||
              (also?.call(library, item.kind) ?? false))) {
        // Another item at the same path starts over.
        return KeyedSubtree(
          key: ValueKey(item),
          child: builder(active, library, item),
        );
      }
      final strings = AppLocalizations.of(context);
      return AlertDialog(
        scrollable: true,
        content: Text(item == null ? strings.pageUnknown : strings.notOffered),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      );
    },
  );
}

class _SheetPage extends Page<void> {
  const _SheetPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => ModalBottomSheetRoute<void>(
    settings: this,
    isScrollControlled: true,
    useSafeArea: true,
    // A drag would close it while a change is being sent.
    enableDrag: false,
    barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    builder: (context) => child,
  );
}

class _DialogPage extends Page<void> {
  const _DialogPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => DialogRoute<void>(
    context: context,
    settings: this,
    builder: (context) => child,
  );
}
