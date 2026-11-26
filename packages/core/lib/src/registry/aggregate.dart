import '../module/result.dart';
import '../module/service_failure.dart';
import 'active_instance.dart';

/// One instance's part of an [Aggregate].
final class InstanceResult<R> {
  /// Creates an [InstanceResult].
  const InstanceResult(this.instance, [this.result]);

  /// Whose it is.
  final ActiveInstance instance;

  /// Null while the instance has not answered.
  final Result<R, ServiceFailure>? result;
}

/// The answers of several instances to the same read, as far as they are in.
final class Aggregate<R> {
  /// Creates an [Aggregate].
  const Aggregate(this.parts);

  /// One for each instance asked, in the instances' order.
  final List<InstanceResult<R>> parts;

  /// Whether every instance has answered.
  bool get isComplete => parts.every((part) => part.result != null);

  /// What the instances that succeeded gave.
  List<(ActiveInstance, R)> get values => [
    for (final part in parts)
      if (part.result case Ok(:final value)) (part.instance, value),
  ];

  /// The instances that failed, to say so beside what the others gave.
  List<(ActiveInstance, ServiceFailure)> get failures => [
    for (final part in parts)
      if (part.result case Err(:final error)) (part.instance, error),
  ];
}
