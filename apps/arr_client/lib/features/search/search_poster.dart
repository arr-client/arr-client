import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/providers.dart';
import 'search_hit.dart';

const searchPosterSize = Size(80, 120);

/// The poster of a result, or a placeholder where there is none to load.
class SearchPoster extends ConsumerWidget {
  const SearchPoster({required this.hit, super.key});

  final SearchHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The loader reads the preference when it makes the image: made again when
    // it changes.
    ref.watch(
      preferencesProvider.select((value) => value.loadThirdPartyArtwork),
    );
    final id = hit.artworkInstanceId;
    final artwork = id == null
        ? null
        : ref.watch(scopeProvider)?.instance(id)?.context.artwork;
    return SizedBox.fromSize(
      size: searchPosterSize,
      child: ArtworkPoster(
        kind: hit.kind,
        images: hit.images,
        artwork: artwork,
        width: searchPosterSize.width,
      ),
    );
  }
}
