import 'package:material_ui/material_ui.dart';

/// Calls [onShown] each time [child] comes on screen, and again when [subject],
/// what it shows, changes while it is there.
///
/// A tab or destination that is not selected, and a page covered by another,
/// have their tickers turned off, which is how this knows. A dialog covers
/// nothing.
class OnShown extends StatefulWidget {
  const OnShown({
    required this.onShown,
    required this.child,
    this.subject,
    super.key,
  });

  /// Called while widgets are being built, before [child] is: it may look at
  /// the providers but must put off changing them. [first] is true for the
  /// first time.
  final void Function({required bool first}) onShown;

  final Object? subject;
  final Widget child;

  @override
  State<OnShown> createState() => _OnShownState();
}

class _OnShownState extends State<OnShown> {
  bool? _visible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final first = _visible == null;
    final shown = visible && _visible != true;
    _visible = visible;
    if (shown) widget.onShown(first: first);
  }

  @override
  void didUpdateWidget(OnShown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subject != oldWidget.subject && (_visible ?? false)) {
      widget.onShown(first: false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
