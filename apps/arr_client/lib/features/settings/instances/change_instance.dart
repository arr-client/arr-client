import 'package:core/core.dart';

/// Saves a new [name] or [enabled] of the instance [id] and leaves the rest as
/// it is saved now, credential included. Null if it was saved or the instance is
/// gone, and otherwise why it was refused.
Future<RuleViolation?> changeInstance(
  ProfileRepository profiles,
  String id, {
  String? name,
  bool? enabled,
}) async {
  // Read here: what the screen shows may be out of date.
  final saved = await profiles.instance(id);
  if (saved == null) return null;
  final result = await profiles.updateInstance(
    id,
    InstanceDraft(
      name: name ?? saved.name,
      serviceType: saved.serviceType,
      url: saved.url,
      authKind: saved.authKind,
      customCa: saved.customCa,
      enabled: enabled ?? saved.enabled,
      links: saved.links,
    ),
  );
  return switch (result) {
    Ok() => null,
    Err(:final error) => error,
  };
}
