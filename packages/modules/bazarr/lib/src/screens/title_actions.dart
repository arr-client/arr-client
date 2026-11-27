/// Searching, downloading, deleting and synchronizing: confirmation where it is
/// needed, sending and saying how it went. Nothing is sent a second time.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/bazarr_localizations.dart';
import 'labels.dart';
import 'read_controllers.dart';
import 'requests.dart';

/// Has the instance called [name] find and download [language].
Future<void> searchSubtitle(
  BuildContext context,
  WidgetRef ref,
  MediaKey target,
  String name,
  SubtitleLanguage language,
) => _send(
  context,
  ref,
  target,
  name,
  () => target.source.provider.autoSearch(target.media, language),
  queued: true,
  acceptedMessage: BazarrLocalizations.of(context).searchSent(name),
);

/// Has the instance called [name] download [candidate]. False if nothing was
/// sent or the server refused, so that it may be asked again.
Future<bool> downloadSubtitle(
  BuildContext context,
  WidgetRef ref,
  MediaKey target,
  String name,
  SubtitleCandidate candidate,
) => _send(
  context,
  ref,
  target,
  name,
  () => target.source.provider.download(target.media, candidate),
  queued: true,
  acceptedMessage: BazarrLocalizations.of(context).downloadSent(name),
);

/// Asks for confirmation naming [file], then deletes it.
Future<void> deleteSubtitle(
  BuildContext context,
  WidgetRef ref,
  MediaKey target,
  String name,
  SubtitleFile file,
) {
  final strings = BazarrLocalizations.of(context);
  return _confirmed(
    context,
    ref,
    target,
    name,
    file,
    title: strings.deleteTitle,
    consequence: strings.deleteConsequence(
      languageLabel(strings, file.language),
      name,
    ),
    confirmLabel: strings.deleteButton,
    destructive: true,
    write: () => target.source.provider.delete(file),
    // Every supported Bazarr has deleted the file when it answers.
    queued: false,
    acceptedMessage: strings.deleted(name),
  );
}

/// Asks for confirmation naming [file], then has it synchronized.
Future<void> syncSubtitle(
  BuildContext context,
  WidgetRef ref,
  MediaKey target,
  String name,
  SubtitleFile file,
) {
  final strings = BazarrLocalizations.of(context);
  return _confirmed(
    context,
    ref,
    target,
    name,
    file,
    title: strings.syncTitle,
    consequence: strings.syncConsequence(name),
    confirmLabel: strings.syncButton,
    destructive: false,
    write: () => target.source.provider.sync(file),
    queued: true,
    acceptedMessage: strings.syncSent(name),
  );
}

Future<void> _confirmed(
  BuildContext context,
  WidgetRef ref,
  MediaKey target,
  String name,
  SubtitleFile file, {
  required String title,
  required String consequence,
  required String confirmLabel,
  required bool destructive,
  required ServiceResult<void> Function() write,
  required bool queued,
  required String acceptedMessage,
}) async {
  final strings = BazarrLocalizations.of(context);
  // Taken now: an edit of the instance takes the screen from under the dialog.
  final messenger = ScaffoldMessenger.of(context);
  void say(String message) {
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  final confirmed = await showConfirmDialog(
    context,
    title: title,
    target: pathText(file.path),
    consequence: consequence,
    confirmLabel: confirmLabel,
    destructive: destructive,
  );
  if (!confirmed) return;
  if (!context.mounted) {
    say(strings.serviceChanged(name));
    return;
  }

  // The screen may have been read again while the dialog was open.
  final stillListed = switch (ref.read(titleProvider(target))) {
    ViewData(:final value, staleness: null) => value.files.any(
      (now) => now.path == file.path,
    ),
    _ => false,
  };
  if (!stillListed) {
    say(strings.fileChanged);
    return;
  }
  await _send(
    context,
    ref,
    target,
    name,
    write,
    queued: queued,
    acceptedMessage: acceptedMessage,
  );
}

Future<bool> _send(
  BuildContext context,
  WidgetRef ref,
  MediaKey target,
  String name,
  ServiceResult<void> Function() write, {
  required bool queued,
  required String acceptedMessage,
}) async {
  final strings = BazarrLocalizations.of(context);
  // Null if another change of it got in first.
  final sending = ref
      .read(requestsProvider.notifier)
      .send(target.source, target.media, write, queued: queued);
  if (sending == null) return false;

  // The screen may be left before the answer.
  void reload() {
    if (context.mounted) {
      unawaited(ref.read(titleProvider(target).notifier).reload());
    }
  }

  ServiceFailure? failure;
  final result = await runAction<void>(
    context,
    action: () async {
      final result = await sending;
      if (result case Err(:final error)) failure = error;
      return result;
    },
    acceptedMessage: acceptedMessage,
    // The server's own words can quote paths and addresses.
    describeFailure: (message) => switch (failure) {
      OutcomeUnknown() => strings.outcomeUnknown(name),
      Validation() => strings.refused(name),
      _ => message,
    },
    onRefresh: reload,
    onGone: reload,
  );
  // What the server has done when it answers is read at once.
  if (!queued && result is Ok) reload();
  return switch (result) {
    Ok() || Err(error: OutcomeUnknown()) => true,
    Err() => false,
  };
}
