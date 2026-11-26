import 'package:material_ui/material_ui.dart';

import 'queue_controller.dart';
import 'visible_watch.dart';

/// Has the queue read for as long as [child] is on screen.
class QueueWatch extends StatelessWidget {
  const QueueWatch({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => VisibleWatch(
    watch: (ref) => ref.read(queueProvider.notifier).watch(),
    child: child,
  );
}
