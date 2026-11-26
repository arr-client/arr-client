/// Confirming an import, sending it and saying how that went.
library;

import 'package:flutter/widgets.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'import_file.dart';
import 'import_labels.dart';
import 'manual_import_controller.dart';

/// Shows what importing [files] will do and, once confirmed, sends it.
Future<void> confirmImport(
  BuildContext context, {
  required String instanceName,
  required ManualImportState state,
  required List<ImportFile> files,
  required ManualImportController controller,
}) async {
  final strings = AppLocalizations.of(context);

  String describe(ImportFile file) {
    final candidate = file.candidate;
    return [
      file.name,
      importMatchLabel(strings, state, candidate),
      if (state.needsEpisodes) importEpisodesLabel(strings, state, candidate),
      [
        importQualityLabel(strings, candidate),
        if (candidate.languages.isNotEmpty)
          importLanguagesLabel(strings, candidate),
      ].join(' · '),
      if (candidate.rejections.isNotEmpty) ...[
        strings.manualImportRejected,
        ...candidate.rejections,
      ],
      if (file.earlierRejections.isNotEmpty) ...[
        strings.manualImportRejectedBefore,
        ...file.earlierRejections,
      ],
    ].join('\n');
  }

  final rejected = files.where((file) => file.isRejected).length;

  // What two files must not both be: a movie, or an episode of a series.
  final taken = <Object>{};
  var same = false;
  for (final file in files) {
    final match = file.candidate.matchedRef;
    final keys = state.needsEpisodes
        ? [for (final id in file.candidate.episodeIds) (match, id)]
        : [match];
    for (final key in keys) {
      if (!taken.add(key ?? file)) same = true;
    }
  }

  final confirmed = await showConfirmDialog(
    context,
    title: strings.manualImportConfirmTitle(files.length),
    target: strings.manualImportSummary(files.length, instanceName),
    consequence: [
      strings.manualImportConsequence(instanceName),
      if (rejected > 0) strings.manualImportConsequenceRejected(rejected),
      if (files.any((file) => file.unchecked))
        strings.manualImportConsequenceUnchecked,
      if (same) strings.manualImportConsequenceSame,
      if (state.outcomeUnknown) strings.manualImportConsequenceUnknown,
    ].join('\n\n'),
    options: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final file in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(describe(file)),
          ),
      ],
    ),
    confirmLabel: strings.manualImportAction(files.length),
  );
  if (!confirmed || !context.mounted) return;

  await runAction(
    context,
    action: () =>
        controller.importFiles([for (final file in files) file.candidate]),
    acceptedMessage: strings.manualImportAccepted(instanceName),
    describeFailure: (message) => strings.queueFailureOn(instanceName, message),
    onRefresh: controller.reload,
    onGone: controller.reload,
  );
}
