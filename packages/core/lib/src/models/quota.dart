import 'quota_usage.dart';

/// How much a user may still request.
final class Quota {
  /// Creates a [Quota].
  const Quota({this.movies, this.series});

  /// Movie quota.
  final QuotaUsage? movies;

  /// Series quota.
  final QuotaUsage? series;
}
