import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../format/format_bytes.dart';
import '../format/format_duration.dart';
import '../l10n/generated/ui_localizations.dart';
import 'release_text.dart';

/// How the grab of a release stands.
enum GrabMark {
  /// Sent and not answered.
  sending,

  /// The server accepted it.
  accepted,

  /// It may or may not have reached the server.
  unknown,
}

/// One release: what it is, why the server would not grab it, and its grab.
///
/// The addresses and the guid of a release can hold keys: they are never shown.
class ReleaseRow extends StatelessWidget {
  /// Creates a [ReleaseRow].
  const ReleaseRow({
    required this.release,
    required this.mark,
    required this.unknownNote,
    required this.onGrab,
    this.showScore = true,
    super.key,
  });

  /// The release.
  final Release release;

  /// How a grab of it stands; null if none was sent.
  final GrabMark? mark;

  /// Said, localized, while [mark] is [GrabMark.unknown]: where to look for it.
  final String unknownNote;

  /// Null while nothing may be grabbed.
  final VoidCallback? onGrab;

  /// False for a service that does not score releases.
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    final strings = UiLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = releaseTitle(context, release);
    final age = release.ageHours;
    final languages = releaseLanguageNames(release);
    // What the server does not say is left out.
    final facts = [
      if (releaseIndexerName(release) case final name?)
        strings.releaseIndexer(name),
      switch (release.protocol) {
        DownloadProtocol.torrent => strings.releaseTorrent,
        DownloadProtocol.usenet => strings.releaseUsenet,
        DownloadProtocol.unknown => null,
      },
      if (release.size > 0)
        strings.releaseSize(formatBytes(context, release.size)),
      if (age.isFinite && age >= 0)
        strings.releaseAge(
          formatDuration(context, Duration(minutes: (age * 60).round())),
        ),
      if (releaseQualityName(release) case final name?)
        strings.releaseQuality(name),
      if (languages.isNotEmpty) strings.releaseLanguages(languages.join(', ')),
      if (release.protocol != DownloadProtocol.usenet) ...[
        if (release.seeders case final count?) strings.releaseSeeders(count),
        if (release.leechers case final count?) strings.releaseLeechers(count),
      ],
      if (showScore) strings.releaseScore(release.score),
    ].nonNulls;
    final reasons = releaseRejections(context, release);
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
                  Text(unknownNote),
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
