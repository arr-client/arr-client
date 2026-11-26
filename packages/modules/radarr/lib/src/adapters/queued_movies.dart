import 'package:core/core.dart';

import '../api/radarr_api.dart';

/// The movies that have a download in the queue.
ServiceResult<Set<int>> queuedMovies(RadarrApi api) async =>
    switch (await api.queue()) {
      Ok(:final value) => Ok({
        for (final download in value) ?download.itemRef?.remoteId,
      }),
      // NotFound would say that what was asked for is gone.
      Err(error: NotFound()) => const Err(ServerError(statusCode: 404)),
      Err(:final error) => Err(error),
    };
