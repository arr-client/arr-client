/// The seasons the request screen chooses from.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/seasons.dart';
import 'seerr_source.dart';

/// One variant of one series of one instance.
typedef SeasonsKey = ({SeerrSource source, int tmdbId, bool is4k});

/// Its seasons, while a screen shows them.
final seasonsProvider = FutureProvider.autoDispose
    .family<Result<SeasonChoices, ServiceFailure>, SeasonsKey>(
      (ref, key) => key.source.guard(
        () => key.source.seasons.seasons(key.tmdbId, is4k: key.is4k),
      ),
    );
