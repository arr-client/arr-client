import 'package:flutter/widgets.dart';

import '../models/item_ref.dart';
import 'detail_slot_name.dart';
import 'detail_slot_scope.dart';

/// A named place a module puts on its detail screen. It shows what the app's
/// [DetailSlotScope] builds for it, and nothing without one.
class DetailSlot extends StatelessWidget {
  const DetailSlot(this.name, {required this.item, this.parent, super.key});

  final DetailSlotName name;

  /// The item the screen shows.
  final ItemRef item;

  /// What [item] belongs to, such as an episode's series.
  final ItemRef? parent;

  @override
  Widget build(BuildContext context) =>
      DetailSlotScope.maybeOf(context)?.builder(context, this) ??
      const SizedBox.shrink();
}
