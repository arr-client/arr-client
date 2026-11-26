import 'package:flutter/widgets.dart';

import 'detail_slot.dart';

/// Placed by the app above module screens to fill their [DetailSlot]s.
class DetailSlotScope extends InheritedWidget {
  /// Creates a [DetailSlotScope].
  const DetailSlotScope({
    required this.builder,
    required super.child,
    super.key,
  });

  /// Builds the content of a slot; an empty box when there is nothing to show.
  final Widget Function(BuildContext context, DetailSlot slot) builder;

  /// The nearest scope, if any.
  static DetailSlotScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailSlotScope>();

  @override
  bool updateShouldNotify(DetailSlotScope oldWidget) =>
      builder != oldWidget.builder;
}
