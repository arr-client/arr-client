/// Grabbing a result: confirmation where it is needed, sending and saying how
/// it went.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/prowlarr_localizations.dart';
import 'grabs.dart';
import 'prowlarr_source.dart';

/// Has the instance called [name] download [release], once the user has
/// confirmed it where an earlier grab of it has an unknown outcome. The outcome
/// is shown also if the screen has been left.
///
/// The server's own words for a refusal are never shown: they can quote
/// addresses that hold keys.
///
/// [context] must outlive the result's row, and go with the instance's screen.
Future<void> grabResult(
  BuildContext context,
  WidgetRef ref,
  ProwlarrSource source,
  String name,
  Release release,
) async {
  final strings = ProwlarrLocalizations.of(context);
  final grabs = ref.read(grabsProvider.notifier);
  // Taken now: an edit of the instance takes the screen from under the dialog.
  final messenger = ScaffoldMessenger.of(context);
  final title = releaseTitle(context, release);
  final mark = ref.read(grabsProvider)[grabKey(source.instanceId, release)];
  if (mark == GrabMark.sending || mark == GrabMark.accepted) return;

  if (mark == GrabMark.unknown) {
    final confirmed = await showConfirmDialog(
      context,
      title: strings.grabAgainTitle,
      target: [title, ?releaseIndexerName(release)].join('\n'),
      consequence: strings.grabUnknown,
      confirmLabel: strings.grabAgainButton,
      destructive: false,
    );
    if (!confirmed) return;
  }

  if (!context.mounted) {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.grabServiceChanged(name))),
      );
    }
    return;
  }

  // Null if another grab of it got in first, which then says how it went.
  final sending = grabs.grab(source, release);
  if (sending == null) return;
  ServiceFailure? failure;
  await runAction<void>(
    context,
    action: () async {
      final result = await sending;
      if (result case Err(:final error)) failure = error;
      return result;
    },
    acceptedMessage: strings.grabAccepted(name, title),
    describeFailure: (message) => switch (failure) {
      OutcomeUnknown() => strings.grabOutcomeUnknown(title, name),
      // The server forgets what a search found after a while.
      NotFound() => strings.grabFailed(title, strings.grabExpired),
      Conflict() => strings.grabFailed(title, strings.grabIndexerFailed),
      ServerError(statusCode: 500) => strings.grabFailed(
        title,
        strings.grabNoClient,
      ),
      Validation() => strings.grabFailed(title, strings.grabRefused),
      _ => strings.grabFailed(title, message),
    },
    // The result's mark says what is known; searching again takes minutes.
    onRefresh: () {},
  );
}
