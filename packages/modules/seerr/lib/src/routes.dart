/// The paths of the Seerr screens, which the module's capabilities point to.
/// Those of the lists of requests and issues have no screen yet (T130).
library;

import 'package:core/core.dart';

/// Discovery.
const discoverPattern = 'seerr/discover';

/// One title. `mediaType` is a [DiscoveryMediaType] name.
const titlePattern = 'seerr/titles/:mediaType/:tmdbId';

/// Requesting one title; the query `is4k` chooses the variant.
const requestPattern = 'seerr/titles/:mediaType/:tmdbId/request';

/// What the user may still request. Only the module's screens lead to it.
const quotaPattern = 'seerr/quota';

/// The list of requests.
const requestsPattern = 'seerr/requests';

/// The list of issues.
const issuesPattern = 'seerr/issues';

/// [pattern] filled in with [title].
String titlePath(String pattern, DiscoveryTitle title) => pattern
    .replaceFirst(':mediaType', title.mediaType.name)
    .replaceFirst(':tmdbId', '${title.tmdbId}');
