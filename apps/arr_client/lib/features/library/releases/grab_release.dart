/// Grabbing a release: confirmation where it is needed, sending and saying how
/// it went.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'release_grabs.dart';
import 'release_view.dart';

/// Has [instance] download [release], once the user has confirmed it where the
/// release is rejected or unmatched, or an earlier grab of it has an unknown
/// outcome. The outcome is shown also if the screen has been left.
///
/// [context] must outlive the release's row.
Future<void> grabRelease(
  BuildContext context,
  WidgetRef ref,
  ActiveInstance instance,
  Release release,
) async {
  final strings = AppLocalizations.of(context);
  final grabs = ref.read(releaseGrabsProvider.notifier);
  // Taken now: an edit of the instance takes the screen from under the dialog.
  final messenger = ScaffoldMessenger.of(context);
  final name = instance.instance.name;
  final title = releaseTitle(context, release);
  final mark = ref.read(
    releaseGrabsProvider,
  )[grabKey(instance.instance.id, release)];
  if (mark == GrabMark.sending || mark == GrabMark.accepted) return;
  final unknownBefore = mark == GrabMark.unknown;

  if (unknownBefore || needsConfirmation(release)) {
    final reasons = releaseRejections(context, release);
    final confirmed = await showConfirmDialog(
      context,
      title: reasons.isNotEmpty
          ? strings.releaseConfirmRejectedTitle
          : !release.downloadAllowed
          ? strings.releaseConfirmUnmatchedTitle
          : strings.releaseConfirmAgainTitle,
      target: [
        title,
        if (serverText(release.indexer) case final indexer?)
          strings.releaseIndexer(indexer),
      ].join('\n'),
      consequence: [
        if (unknownBefore) strings.releaseGrabUnknown,
        if (!release.downloadAllowed) strings.releaseConfirmUnmatched,
        if (reasons.isNotEmpty)
          strings.releaseConfirmReasons(reasons.join('\n')),
      ].join('\n\n'),
      confirmLabel: strings.releaseConfirmButton,
      destructive: false,
    );
    if (!confirmed) return;
  }

  if (!context.mounted || !instance.isCurrent) {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.releaseServiceChanged(name))),
      );
    }
    return;
  }

  // Null if another grab of it got in first, which then says how it went.
  final sending = grabs.grab(instance, release);
  if (sending == null) return;
  ServiceFailure? failure;
  await runAction<void>(
    context,
    action: () async {
      final result = await sending;
      if (result case Err(:final error)) failure = error;
      return result;
    },
    acceptedMessage: strings.releaseGrabAccepted(name, title),
    describeFailure: (message) => switch (failure) {
      OutcomeUnknown() => strings.releaseGrabOutcomeUnknown(title, name),
      // The server forgets what a search found after a while.
      NotFound() => strings.releaseGrabFailed(title, strings.releaseGrabGone),
      _ => strings.releaseGrabFailed(title, message),
    },
    // The release's mark says what is known; searching again takes minutes.
    onRefresh: () {},
  );
}
