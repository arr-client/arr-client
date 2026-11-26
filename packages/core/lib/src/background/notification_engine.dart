import '../logging/logger.dart';
import '../registry/active_instance.dart';
import '../registry/profile_scope.dart';
import '../storage/database.dart';
import 'notice.dart';
import 'notification_event_type.dart';

/// Finds what to notify of, from capabilities only (data-model.md
/// NotificationSubscription and EventMarker).
///
/// It keeps nothing in memory between calls: the background isolate has its own
/// database connection and may be new at every check.
class NotificationEngine {
  /// Creates a [NotificationEngine].
  NotificationEngine({required AppDatabase database, required Logger log});

  /// The events the user has enabled for an instance.
  Future<Set<NotificationEventType>> subscribed(String instanceId) =>
      throw UnimplementedError();

  /// Enables [type] for [instance] and takes its baseline, without notifying.
  /// If the instance does not answer, the first successful check takes it.
  Future<void> subscribe(ActiveInstance instance, NotificationEventType type) =>
      throw UnimplementedError();

  /// Disables [type] for an instance.
  Future<void> unsubscribe(String instanceId, NotificationEventType type) =>
      throw UnimplementedError();

  /// Starts [instances] again from their current state, without notifying: call
  /// with a profile's instances when it is activated, and with an instance when
  /// it is re-enabled. One that does not answer starts at its first successful
  /// check.
  Future<void> initialise(Iterable<ActiveInstance> instances) =>
      throw UnimplementedError();

  /// Checks the instances of [scope] and returns what is new since the last
  /// check, each event once. More than five events of one instance are one
  /// [SummaryNotice].
  Future<List<Notice>> check(ProfileScope scope) => throw UnimplementedError();
}
