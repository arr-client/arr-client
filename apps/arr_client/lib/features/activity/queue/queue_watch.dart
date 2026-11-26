import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'queue_controller.dart';

/// Has the queue read for as long as [child] is on screen.
///
/// A tab or destination that is not selected, and a page covered by another,
/// have their tickers turned off, which is how this knows. A dialog covers
/// nothing.
class QueueWatch extends ConsumerStatefulWidget {
  const QueueWatch({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<QueueWatch> createState() => _QueueWatchState();
}

class _QueueWatchState extends ConsumerState<QueueWatch> {
  void Function()? _release;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      _release ??= ref.read(queueProvider.notifier).watch();
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
