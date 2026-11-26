import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import '../../activity/history/server_text.dart';
import 'release_grabs.dart';
import 'release_view.dart';

/// The title of [release] as harmless text.
String releaseTitle(AppLocalizations strings, Release release) =>
    serverText(release.title) ?? strings.releaseNoTitle;

/// Why [release] was rejected, as harmless text.
List<String> rejectionReasons(AppLocalizations strings, Release release) => [
  for (final reason in release.rejections)
    serverText(reason) ?? strings.releaseReasonMissing,
];

/// One release: what it is, why the server would not grab it, and its grab.
class ReleaseTile extends StatelessWidget {
  const ReleaseTile({
    required this.release,
    required this.mark,
    required this.onGrab,
    super.key,
  });

  final Release release;

  /// How a grab of it stands; null if none was sent.
  final GrabMark? mark;

  /// Null while nothing may be grabbed.
  final VoidCallback? onGrab;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = releaseTitle(strings, release);
    final age = release.ageHours;
    final languages = languageNames(release);
    // What the server does not say is left out.
    final facts = [
      if (indexerName(release) case final name?) strings.releaseIndexer(name),
      switch (release.protocol) {
        DownloadProtocol.torrent => strings.queueTorrent,
        DownloadProtocol.usenet => strings.queueUsenet,
        DownloadProtocol.unknown => null,
      },
      if (release.size > 0)
        strings.releaseSize(formatBytes(context, release.size)),
      if (age.isFinite && age >= 0)
        strings.releaseAge(
          formatDuration(context, Duration(minutes: (age * 60).round())),
        ),
      if (qualityName(release) case final name?) strings.releaseQuality(name),
      if (languages.isNotEmpty) strings.releaseLanguages(languages.join(', ')),
      if (release.protocol != DownloadProtocol.usenet) ...[
        if (release.seeders case final count?) strings.releaseSeeders(count),
        if (release.leechers case final count?) strings.releaseLeechers(count),
      ],
      strings.releaseScore(release.score),
    ].nonNulls;
    final reasons = rejectionReasons(strings, release);
    final note = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final fact in facts) Text(fact, style: note),
                if (reasons.isNotEmpty || !release.downloadAllowed) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: MediaQuery.textScalerOf(context).scale(16),
                        color: colors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!release.downloadAllowed)
                              Text(strings.releaseUnmatched),
                            if (reasons.isNotEmpty) ...[
                              Text(strings.releaseRejected),
                              for (final reason in reasons) Text(reason),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (mark == GrabMark.unknown) ...[
                  const SizedBox(height: 8),
                  Text(strings.releaseGrabUnknown),
                ],
              ],
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: switch (mark) {
              GrabMark.sending => _Status(
                strings.releaseGrabSending,
                const SizedBox.square(
                  dimension: 16,
                  // The text beside it says it.
                  child: ExcludeSemantics(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              GrabMark.accepted => _Status(
                strings.releaseGrabSent,
                const Icon(Icons.check, size: 16),
              ),
              GrabMark.unknown || null => TextButton(
                onPressed: onGrab,
                child: Text(
                  strings.releaseGrab,
                  semanticsLabel: strings.releaseGrabOf(title),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// What stands in place of the grab button, as high as it is.
class _Status extends StatelessWidget {
  const _Status(this.text, this.leading);

  final String text;
  final Widget leading;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 8),
          Flexible(child: Text(text)),
        ],
      ),
    ),
  );
}
