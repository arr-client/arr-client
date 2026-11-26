import 'package:material_ui/material_ui.dart';

import 'client_progress_controller.dart';
import 'visible_watch.dart';

/// Has the download clients read for as long as [child] is on screen.
class ClientProgressWatch extends StatelessWidget {
  const ClientProgressWatch({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => VisibleWatch(
    watch: (ref) => ref.read(clientProgressProvider.notifier).watch(),
    child: child,
  );
}
