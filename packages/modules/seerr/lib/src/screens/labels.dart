/// The words and icons for what a server says about a title.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/generated/seerr_localizations.dart';

/// "Movie" or "Series".
String mediaTypeLabel(SeerrLocalizations strings, DiscoveryMediaType type) =>
    switch (type) {
      DiscoveryMediaType.movie => strings.typeMovie,
      DiscoveryMediaType.series => strings.typeSeries,
    };

/// The kind of poster placeholder.
MediaKind mediaKindOf(DiscoveryMediaType type) => switch (type) {
  DiscoveryMediaType.movie => MediaKind.movie,
  DiscoveryMediaType.series => MediaKind.series,
};

/// The name of a browsable list.
String categoryLabel(SeerrLocalizations strings, DiscoveryCategory category) =>
    switch (category) {
      DiscoveryCategory.trending => strings.categoryTrending,
      DiscoveryCategory.popularMovies => strings.categoryPopularMovies,
      DiscoveryCategory.popularSeries => strings.categoryPopularSeries,
      DiscoveryCategory.upcomingMovies => strings.categoryUpcomingMovies,
      DiscoveryCategory.upcomingSeries => strings.categoryUpcomingSeries,
    };

/// Whether a variant is on the server.
String availabilityLabel(
  SeerrLocalizations strings,
  Availability availability,
) => switch (availability) {
  Availability.unknown => strings.availabilityNone,
  Availability.pending => strings.availabilityPending,
  Availability.processing => strings.availabilityProcessing,
  Availability.partial => strings.availabilityPartial,
  Availability.available => strings.availabilityAvailable,
  Availability.blocklisted => strings.availabilityBlocklisted,
  Availability.deleted => strings.availabilityDeleted,
};

/// The icon that goes with [availabilityLabel].
IconData availabilityIcon(Availability availability) => switch (availability) {
  Availability.unknown => Icons.remove_circle_outline,
  Availability.pending => Icons.schedule,
  Availability.processing => Icons.downloading,
  Availability.partial => Icons.timelapse,
  Availability.available => Icons.check_circle_outline,
  Availability.blocklisted => Icons.block,
  Availability.deleted => Icons.delete_outline,
};

/// Where a request is; null for a status the app does not know.
String? requestStatusLabel(SeerrLocalizations strings, RequestStatus? status) =>
    switch (status) {
      RequestStatus.pending => strings.requestPending,
      RequestStatus.approved => strings.requestApproved,
      RequestStatus.declined => strings.requestDeclined,
      RequestStatus.failed => strings.requestFailedStatus,
      RequestStatus.completed => strings.requestCompleted,
      RequestStatus.unknown || null => null,
    };

/// How much of a quota is used.
String quotaLabel(SeerrLocalizations strings, QuotaUsage usage) =>
    switch ((usage.limit, usage.days)) {
      (null, _) => strings.quotaUnlimited,
      (final limit?, null) => strings.quotaUsed(usage.used, limit),
      (final limit?, final days?) => strings.quotaUsedInDays(
        usage.used,
        limit,
        days,
      ),
    };
