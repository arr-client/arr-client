import 'package:core/core.dart';

/// The answers of every service asked, in the instances' order.
typedef ServiceAnswers<T> = List<ServiceAnswer<T>>;

/// What one service has given for one read.
final class ServiceAnswer<T> {
  const ServiceAnswer({
    required this.instanceId,
    required this.name,
    required this.loading,
    this.value,
    this.fetchedAt,
    this.failure,
  });

  final String instanceId;

  /// The instance's name.
  final String name;

  /// Whether a read is under way.
  final bool loading;

  /// What it last gave; null if it never answered.
  final List<T>? value;

  /// When [value] was read, by the device's clock.
  final DateTime? fetchedAt;

  /// Why the last read failed.
  final ServiceFailure? failure;

  /// While it is read again.
  ServiceAnswer<T> reading() => ServiceAnswer(
    instanceId: instanceId,
    name: name,
    loading: true,
    value: value,
    fetchedAt: fetchedAt,
  );

  /// With the [value] read at [at].
  ServiceAnswer<T> answered(List<T> value, DateTime at) => ServiceAnswer(
    instanceId: instanceId,
    name: name,
    loading: false,
    value: value,
    fetchedAt: at,
  );

  /// What was read before stays.
  ServiceAnswer<T> failed(ServiceFailure failure) => ServiceAnswer(
    instanceId: instanceId,
    name: name,
    loading: false,
    value: value,
    fetchedAt: fetchedAt,
    failure: failure,
  );
}
