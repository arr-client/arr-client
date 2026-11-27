/// What the screens show of a title.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/seerr_localizations.dart';
import 'labels.dart';

/// The poster of [title] at [width].
class TitlePoster extends StatelessWidget {
  /// Creates a [TitlePoster].
  const TitlePoster({
    required this.title,
    required this.artwork,
    required this.width,
    super.key,
  });

  /// Whose poster.
  final DiscoveryTitle title;

  /// Loads it.
  final ArtworkLoader artwork;

  /// Its width; it is half again as high.
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 1.5,
    child: ArtworkPoster(
      kind: mediaKindOf(title.mediaType),
      images: [?title.poster],
      artwork: artwork,
      width: width,
    ),
  );
}

/// What kind of title it is and from when.
String titleFacts(SeerrLocalizations strings, DiscoveryTitle title) => [
  mediaTypeLabel(strings, title.mediaType),
  if (title.year case final year?) '$year',
].join(' · ');

/// An icon with the words it stands beside, which say the same.
class IconLine extends StatelessWidget {
  /// Creates an [IconLine].
  const IconLine(this.icon, this.text, {super.key});

  /// The icon.
  final IconData icon;

  /// The localized text.
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: MediaQuery.textScalerOf(context).scale(16),
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
