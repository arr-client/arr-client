/// Use of one request quota.
final class QuotaUsage {
  /// Creates a [QuotaUsage].
  const QuotaUsage({required this.used, this.limit, this.days});

  /// Requests counted so far.
  final int used;

  /// Null when unlimited.
  final int? limit;

  /// The period the limit applies to.
  final int? days;
}
