import 'quota_usage.dart';

/// How much a user may still request.
final class Quota {
  const Quota({this.movies, this.series});

  final QuotaUsage? movies;

  final QuotaUsage? series;
}
