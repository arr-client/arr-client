import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Has something read for as long as [child] is on screen.
///
/// A tab or destination that is not selected, and a page covered by another,
/// have their tickers turned off, which is how this knows. A dialog covers
/// nothing.
class VisibleWatch extends ConsumerStatefulWidget {
  const VisibleWatch({required this.watch, required this.child, super.key});

  /// Starts watching, and returns what ends it.
  final void Function() Function(WidgetRef ref) watch;

  final Widget child;

  @override
  ConsumerState<VisibleWatch> createState() => _VisibleWatchState();
}

class _VisibleWatchState extends ConsumerState<VisibleWatch> {
  void Function()? _release;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      _release ??= widget.watch(ref);
    } else {
      _release?.call();
      _release = null;
    }
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
