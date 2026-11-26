import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';
import 'failure_message.dart';

/// Sends one change to a server and tells the user how it went.
///
/// [action] is called exactly once: a change is never retried or queued here.
/// Nothing is reported before it completes, and [acceptedMessage], localized by
/// the caller, only when the server has accepted it. It must not claim more
/// than that: "Search started", not "Movie found".
///
/// - [NotFound]: says the item is gone and calls [onGone].
/// - [OutcomeUnknown]: says so and calls [onRefresh], which loads the real
///   state from the server.
/// - Any other failure: says what happened.
///
/// A failure stays on screen until dismissed. The message is shown, and the
/// callbacks are called, even if the screen that started the action has been
/// left, so the callbacks must not depend on it.
///
/// Returns the result, for what is specific to the caller, such as updating its
/// state or offering to open an item that already exists.
///
/// [context] must be below a `ScaffoldMessenger` that has a `Scaffold`.
Future<Result<T, ServiceFailure>> runAction<T>(
  BuildContext context, {
  required ServiceResult<T> Function() action,
  required String acceptedMessage,
  required VoidCallback onRefresh,
  VoidCallback? onGone,
}) async {
  // Taken before the wait, after which context may be unmounted.
  final messenger = ScaffoldMessenger.of(context);
  final result = await action();

  if (messenger.mounted) {
    final message = switch (result) {
      Ok() => acceptedMessage,
      Err(error: NotFound()) => UiLocalizations.of(messenger.context).itemGone,
      Err(:final error) => failureMessage(messenger.context, error),
    };
    final failed = result is Err;
    final maxHeight = MediaQuery.sizeOf(messenger.context).height / 3;
    // The latest outcome must not wait behind an earlier one.
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          // Server messages can be long.
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(child: Text(message)),
          ),
          persist: failed,
          showCloseIcon: failed,
        ),
      );
  }

  switch (result) {
    case Err(error: NotFound()):
      onGone?.call();
    case Err(error: OutcomeUnknown()):
      onRefresh();
    case Ok() || Err():
      break;
  }
  return result;
}
