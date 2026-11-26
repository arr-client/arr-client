import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../activity/queue/queue_controller.dart';
import '../calendar/on_shown.dart';
import '../calendar/today.dart';
import 'refresh_home.dart';

/// The least time between two reads that coming back to Home causes.
const homeReturnInterval = Duration(seconds: 10);

/// Keeps what Home shows current while the app stays open: reads it again when
/// the user comes back to it, and what was imported when an entry leaves a
/// queue, as one does once it is imported.
class HomeFreshness extends ConsumerStatefulWidget {
  const HomeFreshness({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HomeFreshness> createState() => _HomeFreshnessState();
}

class _HomeFreshnessState extends ConsumerState<HomeFreshness> {
  DateTime? _readAt;

  /// The ids last read of each instance's queue.
  final _queued = <String, Set<int>>{};

  /// The instances whose imports are being read, and those of them to read
  /// once more afterwards, so that at most one such read of each is under way.
  final _reading = <String>{};
  final _again = <String>{};

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      queueProvider,
      (_, queues) => _compare(queues),
      fireImmediately: true,
    );
  }

  void _compare(QueueState state) {
    for (final queue in state.queues) {
      final items = queue.items;
      // Only what was just read says what is no longer there.
      if (items == null || queue.isStale) continue;
      final id = queue.instance.instance.id;
      final now = {for (final item in items) item.id};
      final before = _queued[id];
      _queued[id] = now;
      if (before != null && before.any((item) => !now.contains(item))) {
        scheduleMicrotask(() => unawaited(_readImports(id)));
      }
    }
  }

  Future<void> _readImports(String instanceId) async {
    if (!_reading.add(instanceId)) {
      _again.add(instanceId);
      return;
    }
    do {
      _again.remove(instanceId);
      if (!mounted) break;
      await reloadImports(ref, instanceId: instanceId);
    } while (_again.contains(instanceId));
    _reading.remove(instanceId);
  }

  void _shown({required bool first}) {
    final now = ref.read(clockProvider)();
    // The first time, everything is being read anyway. A clock set back must
    // not stop the reading.
    final last = _readAt;
    if (last != null && now.difference(last).abs() < homeReturnInterval) return;
    _readAt = now;
    if (first) return;
    scheduleMicrotask(() {
      if (mounted) unawaited(reloadHome(ref));
    });
  }

  @override
  Widget build(BuildContext context) =>
      OnShown(onShown: _shown, child: widget.child);
}
