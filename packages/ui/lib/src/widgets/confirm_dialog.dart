import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';

/// Asks the user to confirm an action, returning true only if they press the
/// confirm button. Cancel, the back button and a tap outside return false.
///
/// All texts are localized by the caller. [consequence] says what will happen,
/// and [target] names what is acted on, for example the title of a movie or the
/// titles of the selected items. [confirmLabel] says what the button does, such
/// as "Delete movie".
///
/// [options] are choices shown above the buttons, such as whether to delete
/// files. The widget holds its own state and reports changes to the caller.
///
/// The dialog scrolls with its buttons in place, so [consequence] comes first:
/// however long [target] is, what the button does is not out of sight. Choices
/// follow [target], so where both are there, a long list of names goes in
/// [options], after the choices.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String target,
  required String consequence,
  required String confirmLabel,
  Widget? options,
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(consequence),
            const SizedBox(height: 16),
            Text(target, style: theme.textTheme.titleMedium),
            if (options != null) ...[const SizedBox(height: 16), options],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(UiLocalizations.of(context).cancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
