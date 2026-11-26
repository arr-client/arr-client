import 'package:material_ui/material_ui.dart';

/// Says whether the route it is on is the current one, that is, not covered by
/// another page or dialog: when first built and whenever that changes. A screen
/// stops asking the server about what nobody sees.
///
/// [onChanged] is called while the tree is built, so it must not change state
/// that widgets are built from.
class RouteCurrentListener extends StatefulWidget {
  /// Creates a [RouteCurrentListener].
  const RouteCurrentListener({
    required this.onChanged,
    required this.child,
    super.key,
  });

  /// Told whether the route is current.
  final ValueChanged<bool> onChanged;

  /// What is shown.
  final Widget child;

  @override
  State<RouteCurrentListener> createState() => _RouteCurrentListenerState();
}

class _RouteCurrentListenerState extends State<RouteCurrentListener> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Current where there is no route to be covered.
    widget.onChanged(ModalRoute.isCurrentOf(context) ?? true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
