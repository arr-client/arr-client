/// What an identity may do on a service that has permissions. Names are
/// persisted.
enum ServicePermission {
  /// Request movies.
  requestMovies,

  /// Request series.
  requestSeries,

  /// Request movies in 4K.
  request4kMovies,

  /// Request series in 4K.
  request4kSeries,

  /// Approve, decline, retry and delete requests.
  manageRequests,

  /// Report issues.
  reportIssues,

  /// See issues.
  viewIssues,

  /// Resolve and reopen issues.
  manageIssues,
}
