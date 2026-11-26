/// The paths of the Seerr screens, which the module's capabilities point to.
/// The screens are not built yet (T129, T130), so the module is not registered
/// with the app.
library;

import 'package:core/core.dart';

/// Discovery.
const discoverPattern = 'seerr/discover';

/// One title. `mediaType` is a [DiscoveryMediaType] name.
const titlePattern = 'seerr/titles/:mediaType/:tmdbId';

/// Requesting one title; the query `is4k` chooses the variant.
const requestPattern = 'seerr/titles/:mediaType/:tmdbId/request';

/// The list of requests.
const requestsPattern = 'seerr/requests';

/// The list of issues.
const issuesPattern = 'seerr/issues';

/// [pattern] filled in with [title].
String titlePath(String pattern, DiscoveryTitle title) => pattern
    .replaceFirst(':mediaType', title.mediaType.name)
    .replaceFirst(':tmdbId', '${title.tmdbId}');
