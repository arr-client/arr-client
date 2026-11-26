import 'package:flutter/widgets.dart';

import 'detail_slot.dart';

/// Placed by the app above module screens to fill their [DetailSlot]s.
class DetailSlotScope extends InheritedWidget {
  const DetailSlotScope({
    required this.builder,
    required super.child,
    super.key,
  });

  /// Builds the content of a slot; an empty box when there is nothing to show.
  final Widget Function(BuildContext context, DetailSlot slot) builder;

  static DetailSlotScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailSlotScope>();

  @override
  bool updateShouldNotify(DetailSlotScope oldWidget) =>
      builder != oldWidget.builder;
}
