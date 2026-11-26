import 'package:core/core.dart';

import '../../../app/navigation/locations.dart';

/// Where the screen of [ref], called [title], is on [instance]; null where the
/// instance has no library to show it in.
String? itemLocation(ActiveInstance? instance, ItemRef ref, String title) {
  final library = instance?.capability(CapabilityKind.library);
  if (library == null) return null;
  // A module without detail screens yet throws; the page says so.
  try {
    return library.detailRoute(ref).location;
  } on UnimplementedError {
    return itemPlaceholderLocation(ref.instanceId, title);
  }
}
